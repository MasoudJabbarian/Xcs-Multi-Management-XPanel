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
REPO_URL='https://github.com/MasoudJabbarian/Xcs-Multi-Management-XPanel.git'
REPO_REF='ubuntu-24-support'
SOURCE_DIR='/tmp/xcs-panel-source'
PHP_MAJOR_MINOR='8.1'

if [[ ${EUID} -ne 0 ]]; then
    echo -e "${RED}Please run as root.${ENDCOLOR}" >&2
    exit 1
fi

source /etc/os-release
if [[ ${ID:-} != 'ubuntu' || "${VERSION_ID}" != '22.04' ]]; then
    echo -e "${RED}This installer is specifically for Ubuntu 22.04.${ENDCOLOR}" >&2
    echo "Detected: ${PRETTY_NAME:-unknown}" >&2
    exit 1
fi

read -rp 'Panel public IP/hostname: ' PANEL_HOST
[[ ${PANEL_HOST} =~ ^[A-Za-z0-9.-]+$ ]] || { echo 'Invalid panel IP/hostname.' >&2; exit 1; }

read -rp 'Panel admin username [admin]: ' ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
[[ ${ADMIN_USERNAME} =~ ^[A-Za-z0-9._-]{1,64}$ ]] || { echo 'Invalid admin username.' >&2; exit 1; }

read -rsp 'Panel admin password [leave blank for a random password]: ' ADMIN_PASSWORD
printf '\n'
if [[ -z "${ADMIN_PASSWORD}" ]]; then
    ADMIN_PASSWORD=$(openssl rand -hex 16)
fi
[[ ${#ADMIN_PASSWORD} -ge 8 ]] || { echo 'Admin password must be at least 8 characters.' >&2; exit 1; }

read -rp 'Panel port [random]: ' PANEL_PORT
if [[ -z "${PANEL_PORT}" ]]; then
    while :; do
        PANEL_PORT=$(shuf -i 10000-60000 -n 1)
        ss -ltnH | awk '{print $4}' | grep -Eq ":${PANEL_PORT}$" || break
    done
fi
[[ ${PANEL_PORT} =~ ^[0-9]+$ && ${PANEL_PORT} -ge 1024 && ${PANEL_PORT} -le 65535 ]] || { echo 'Invalid panel port.' >&2; exit 1; }
if ss -ltnH | awk '{print $4}' | grep -Eq ":${PANEL_PORT}$"; then
    echo -e "${RED}Port ${PANEL_PORT} is already in use.${ENDCOLOR}" >&2
    exit 1
fi

DB_PASSWORD="$(openssl rand -hex 24)"
XCS_FIXER_TOKEN="$(openssl rand -hex 32)"

export XCS_PANEL_HOST="${PANEL_HOST}"
export XCS_PANEL_PORT="${PANEL_PORT}"
export XCS_ADMIN_USERNAME="${ADMIN_USERNAME}"
export XCS_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
export XCS_DB_PASSWORD="${DB_PASSWORD}"
export XCS_FIXER_TOKEN

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 mariadb-server curl unzip zip git cron openssl ca-certificates composer \
    php8.1 php8.1-cli php8.1-common php8.1-mysql php8.1-mbstring php8.1-xml php8.1-curl \
    php8.1-bcmath php8.1-zip php8.1-intl php8.1-gd

systemctl enable --now mariadb apache2 cron
a2enmod rewrite >/dev/null

php -r 'exit(PHP_MAJOR_VERSION === 8 && PHP_MINOR_VERSION === 1 ? 0 : 1);' || {
    echo -e "${RED}PHP 8.1 is required after package installation.${ENDCOLOR}" >&2
    php -v >&2 || true
    exit 1
}

rm -rf "${SOURCE_DIR}"
git clone --depth 1 --branch "${REPO_REF}" --single-branch "${REPO_URL}" "${SOURCE_DIR}"
[[ -d "${SOURCE_DIR}/Web Panel/app" ]] || { echo 'Laravel source directory was not found at Web Panel/app.' >&2; exit 1; }

rm -rf "${APP_ROOT}"
mkdir -p "${APP_ROOT}"
cp -a "${SOURCE_DIR}/Web Panel/app/." "${APP_ROOT}/"
rm -rf "${SOURCE_DIR}"

[[ -f "${APP_ROOT}/artisan" ]] || { echo "Laravel artisan was not found in ${APP_ROOT}." >&2; exit 1; }

# Apply all validated production fixes, public assets and remote-user sync
# immediately after the Laravel source is copied to the new server.
chmod +x "${APP_ROOT}/install-fixes.sh"
"${APP_ROOT}/install-fixes.sh" "${APP_ROOT}"

mkdir -p "${APP_ROOT}/storage/backup" "${APP_ROOT}/bootstrap/cache"

DB_PASSWORD_SQL=${DB_PASSWORD//\'/\'\'}
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
    "LOG_LEVEL" => "error",
    "DB_CONNECTION" => "mysql",
    "DB_HOST" => "127.0.0.1",
    "DB_PORT" => "3306",
    "DB_DATABASE" => "Xcs",
    "DB_USERNAME" => "xcs_admin",
    "DB_PASSWORD" => getenv("XCS_DB_PASSWORD"),
    "XCS_FIXER_TOKEN" => getenv("XCS_FIXER_TOKEN"),
];
foreach ($values as $key => $value) {
    $line = $key . "=\"" . str_replace(["\\", "\""], ["\\\\", "\\\""], $value) . "\"";
    $pattern = "/^" . preg_quote($key, "/") . ".*$/m";
    if (preg_match($pattern, $env)) {
        $env = preg_replace($pattern, $line, $env, 1);
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
if ! grep -qE "^Listen[[:space:]]+${PANEL_PORT}$" /etc/apache2/ports.conf; then
    printf '\nListen %s\n' "${PANEL_PORT}" >> /etc/apache2/ports.conf
fi
apache2ctl configtest
systemctl reload apache2

chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
chmod -R ug+rwX "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
chmod 640 "${APP_ROOT}/.env"
chown www-data:www-data "${APP_ROOT}/.env"

CRON_MARKER='# XCS_FIXER'
CRON_LINE="* * * * * curl -fsS --max-time 60 -H 'X-Xcs-Fixer-Token: ${XCS_FIXER_TOKEN}' 'http://127.0.0.1:${PANEL_PORT}/fixer/exp' >/dev/null 2>&1 ${CRON_MARKER}"
( crontab -l 2>/dev/null | grep -Fv "${CRON_MARKER}" || true; echo "${CRON_LINE}" ) | crontab -

php artisan optimize:clear
php artisan config:cache

cat <<EOF

************ Xcs Ubuntu 22.04 ************
Repository : ${REPO_URL}
Branch     : ${REPO_REF}
Xcs Link   : http://${PANEL_HOST}:${PANEL_PORT}/login
Username   : ${ADMIN_USERNAME}
Password   : ${ADMIN_PASSWORD}

Installation completed successfully.
EOF