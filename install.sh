#!/usr/bin/env bash
set -Eeuo pipefail

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
ENDCOLOR='\e[0m'

APP_ROOT='/var/www/html/app'
DB_NAME='Xcs'
DB_HOST='127.0.0.1'
DB_USER='xcs_admin'
RELEASE_API='https://api.github.com/repos/xpanel-cp/Xcs-Multi-Management-XPanel/releases/tags/xcsv1-0'

if [[ ${EUID} -ne 0 ]]; then
    echo -e "${RED}Please run as root.${ENDCOLOR}" >&2
    exit 1
fi

source /etc/os-release
if [[ ${ID:-} != 'ubuntu' || "${VERSION_ID%%.*}" -lt 24 ]]; then
    echo -e "${RED}This installer supports Ubuntu 24.04 or newer only.${ENDCOLOR}" >&2
    exit 1
fi

read -rp 'Panel public IP/hostname: ' PANEL_HOST
[[ -n "${PANEL_HOST}" ]] || { echo 'Panel IP/hostname is required.' >&2; exit 1; }

read -rp 'Panel admin username [admin]: ' ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
[[ ${ADMIN_USERNAME} =~ ^[A-Za-z0-9._-]{1,64}$ ]] || { echo 'Invalid admin username.' >&2; exit 1; }

read -rsp 'Panel admin password [leave blank for a random password]: ' ADMIN_PASSWORD
printf '\n'
if [[ -z "${ADMIN_PASSWORD}" ]]; then
    ADMIN_PASSWORD=$(openssl rand -hex 16)
fi

read -rp 'Panel port [random]: ' PANEL_PORT
if [[ -z "${PANEL_PORT}" ]]; then
    while :; do
        PANEL_PORT=$(shuf -i 10000-60000 -n 1)
        ss -ltnH | awk '{print $4}' | grep -Eq ":${PANEL_PORT}$" || break
    done
fi
[[ ${PANEL_PORT} =~ ^[0-9]+$ && PANEL_PORT -ge 1024 && PANEL_PORT -le 65535 ]] || { echo 'Invalid panel port.' >&2; exit 1; }

export XCS_PANEL_HOST="${PANEL_HOST}"
export XCS_PANEL_PORT="${PANEL_PORT}"
export XCS_ADMIN_USERNAME="${ADMIN_USERNAME}"
export XCS_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
export XCS_FIXER_TOKEN="$(openssl rand -hex 32)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 mariadb-server curl unzip zip git cron openssl ca-certificates composer \
    php8.3 php8.3-cli php8.3-common php8.3-mysql php8.3-mbstring php8.3-xml php8.3-curl \
    php8.3-bcmath php8.3-zip php8.3-intl

systemctl enable --now mariadb apache2 cron
a2enmod rewrite >/dev/null

RELEASE_URL=$(curl -fsSL "${RELEASE_API}" | grep -m1 '"browser_download_url"' | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/')
[[ -n "${RELEASE_URL}" ]] || { echo 'Unable to determine Xcs release URL.' >&2; exit 1; }
curl -fL "${RELEASE_URL}" -o /tmp/xcs-update.zip
unzip -oq /tmp/xcs-update.zip -d /var/www/html
rm -f /tmp/xcs-update.zip

[[ -d "${APP_ROOT}" ]] || { echo "Application directory ${APP_ROOT} was not found in the release." >&2; exit 1; }
mkdir -p "${APP_ROOT}/storage/backup" "${APP_ROOT}/bootstrap/cache"

DB_PASSWORD_SQL=${ADMIN_PASSWORD//\'/\'\'}
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASSWORD_SQL}';
ALTER USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASSWORD_SQL}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL

cd "${APP_ROOT}"
[[ -f .env ]] || cp .env.example .env

php -r '
$path = ".env";
$env = file_get_contents($path);
$values = [
    "APP_ENV" => "production",
    "APP_DEBUG" => "false",
    "APP_URL" => "http://" . getenv("XCS_PANEL_HOST") . ":" . getenv("XCS_PANEL_PORT"),
    "DB_CONNECTION" => "mysql",
    "DB_HOST" => "127.0.0.1",
    "DB_DATABASE" => "Xcs",
    "DB_USERNAME" => "xcs_admin",
    "DB_PASSWORD" => getenv("XCS_ADMIN_PASSWORD"),
    "XCS_FIXER_TOKEN" => getenv("XCS_FIXER_TOKEN"),
];
foreach ($values as $key => $value) {
    $line = $key . "=\"" . str_replace(["\\", "\""], ["\\\\", "\\\""], $value) . "\"";
    if (preg_match("/^" . preg_quote($key, "/") . "=.*$/m", $env)) {
        $env = preg_replace("/^" . preg_quote($key, "/") . ".*$/m", $line, $env);
    } else {
        $env .= PHP_EOL . $line;
    }
}
file_put_contents($path, $env, LOCK_EX);
'

composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction
php artisan key:generate --force
php artisan config:clear
php artisan migrate --force

php artisan tinker --execute='\App\Models\Admins::updateOrCreate(["username" => getenv("XCS_ADMIN_USERNAME")], ["password" => getenv("XCS_ADMIN_PASSWORD"), "permission" => "admin", "credit" => "0", "status" => "active"]);'

cat > /etc/apache2/sites-available/xcs.conf <<APACHE
<VirtualHost *:${PANEL_PORT}>
    ServerName ${PANEL_HOST}
    DocumentRoot ${APP_ROOT}/public

    <Directory ${APP_ROOT}/public>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/xcs-error.log
    CustomLog \${APACHE_LOG_DIR}/xcs-access.log combined
</VirtualHost>
APACHE

a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite xcs.conf >/dev/null
if ! grep -qE "^Listen ${PANEL_PORT}$" /etc/apache2/ports.conf; then
    printf '\nListen %s\n' "${PANEL_PORT}" >> /etc/apache2/ports.conf
fi
apache2ctl configtest
systemctl reload apache2

chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
chmod -R ug+rwX "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"

# Call the protected maintenance endpoint every minute without deleting the
# existing root crontab.
CRON_MARKER='# XCS_FIXER'
CRON_LINE="* * * * * curl -fsS --max-time 60 -H 'X-Xcs-Fixer-Token: ${XCS_FIXER_TOKEN}' 'http://127.0.0.1:${PANEL_PORT}/fixer/exp' >/dev/null 2>&1 ${CRON_MARKER}"
( crontab -l 2>/dev/null | grep -Fv "${CRON_MARKER}" || true; echo "${CRON_LINE}" ) | crontab -

php artisan optimize:clear

cat <<EOF

************ Xcs Ubuntu 24 ************
Xcs Link : http://${PANEL_HOST}:${PANEL_PORT}/login
Username : ${ADMIN_USERNAME}
Password : ${ADMIN_PASSWORD}

Installation completed successfully.
EOF
