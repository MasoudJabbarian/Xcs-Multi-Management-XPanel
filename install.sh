#!/usr/bin/env bash
set -Eeuo pipefail

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
ENDCOLOR='\e[0m'

APP_ROOT='/var/www/html/app'
WEB_ROOT='/var/www/html/cp'
DB_NAME='Xcs'
DB_HOST='127.0.0.1'
DB_USER='xcs_admin'
RELEASE_API='https://api.github.com/repos/xpanel-cp/Xcs-Multi-Management-XPanel/releases/tags/xcsv1-0'

if [[ ${EUID} -ne 0 ]]; then
    echo -e "${RED}Please run as root.${ENDCOLOR}" >&2
    exit 1
fi

source /etc/os-release
if [[ ${ID:-} != 'ubuntu' ]]; then
    echo -e "${RED}This installer supports Ubuntu only (detected: ${PRETTY_NAME:-unknown}).${ENDCOLOR}" >&2
    exit 1
fi

if [[ "${VERSION_ID%%.*}" -lt 24 ]]; then
    echo -e "${RED}This branch targets Ubuntu 24.04 or newer.${ENDCOLOR}" >&2
    exit 1
fi

read -rp 'Panel public IP/hostname: ' PANEL_HOST
if [[ -z "${PANEL_HOST}" ]]; then
    echo -e "${RED}Panel IP/hostname is required.${ENDCOLOR}" >&2
    exit 1
fi

read -rp 'Panel admin username [admin]: ' ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}
read -rsp 'Panel admin password [leave blank for a random password]: ' ADMIN_PASSWORD
printf '\n'
if [[ -z "${ADMIN_PASSWORD}" ]]; then
    ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)
fi

read -rp 'Panel port [random]: ' PANEL_PORT
if [[ -z "${PANEL_PORT}" ]]; then
    while :; do
        PANEL_PORT=$(shuf -i 10000-60000 -n 1)
        if ! ss -ltnH | awk '{print $4}' | grep -Eq ":${PANEL_PORT}$"; then
            break
        fi
    done
fi
if ! [[ ${PANEL_PORT} =~ ^[0-9]+$ ]] || (( PANEL_PORT < 1024 || PANEL_PORT > 65535 )); then
    echo -e "${RED}Invalid panel port.${ENDCOLOR}" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 mariadb-server curl unzip zip git cron openssl ca-certificates composer php8.3 php8.3-cli php8.3-common php8.3-mysql php8.3-mbstring php8.3-xml php8.3-curl php8.3-bcmath php8.3-zip php8.3-intl

systemctl enable --now mariadb apache2 cron

a2enmod rewrite >/dev/null

if [[ ! -d "${APP_ROOT}" ]]; then
    mkdir -p "${APP_ROOT}"
fi
if [[ ! -d "${WEB_ROOT}" ]]; then
    mkdir -p "${WEB_ROOT}"
fi

# If the release archive is available, install the application without assuming
# an Ubuntu-specific PHP version or Apache service name.
RELEASE_URL=$(curl -fsSL "${RELEASE_API}" | grep -m1 '"browser_download_url"' | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/')
if [[ -z "${RELEASE_URL}" ]]; then
    echo -e "${RED}Unable to determine the Xcs release download URL.${ENDCOLOR}" >&2
    exit 1
fi
curl -fL "${RELEASE_URL}" -o /tmp/xcs-update.zip
unzip -oq /tmp/xcs-update.zip -d /var/www/html
rm -f /tmp/xcs-update.zip

# Create a least-privilege database account. The installer no longer grants
# ALL PRIVILEGES ON *.* to the panel user.
mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '$(printf '%s' "${ADMIN_PASSWORD}" | sed "s/'/''/g")';
ALTER USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '$(printf '%s' "${ADMIN_PASSWORD}" | sed "s/'/''/g")';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL

cd "${APP_ROOT}"

if [[ ! -f .env ]]; then
    cp .env.example .env
fi

php artisan key:generate --force
php artisan config:clear
php artisan cache:clear || true

php -r '
$path = ".env";
$env = file_get_contents($path);
$set = function (&$env, $key, $value) {
    $quoted = str_replace("\\", "\\\\", $value);
    $quoted = str_replace("\"", "\\\"", $quoted);
    if (preg_match("/^" . preg_quote($key, "/") . "=/m", $env)) {
        $env = preg_replace("/^" . preg_quote($key, "/") . ".*$/m", $key . "=\"" . $quoted . "\"", $env);
    } else {
        $env .= "\\n" . $key . "=\"" . $quoted . "\"\\n";
    }
};
$set($env, "APP_ENV", "production");
$set($env, "APP_DEBUG", "false");
$set($env, "APP_URL", "http://' . addslashes($PANEL_HOST) . ':' . (int)$PANEL_PORT . '");
$set($env, "DB_CONNECTION", "mysql");
$set($env, "DB_HOST", "' . addslashes($DB_HOST) . '");
$set($env, "DB_DATABASE", "' . addslashes($DB_NAME) . '");
$set($env, "DB_USERNAME", "' . addslashes($DB_USER) . '");
$set($env, "DB_PASSWORD", "' . addslashes($ADMIN_PASSWORD) . '");
file_put_contents($path, $env);
'

composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction
php artisan migrate --force

# Seed/update the initial administrator using Laravel hashing rather than
# storing the password in plaintext in SQL.
php artisan tinker --execute="\App\Models\Admins::updateOrCreate(['username' => '${ADMIN_USERNAME}'], ['password' => '${ADMIN_PASSWORD}', 'permission' => 'admin', 'credit' => '0', 'status' => 'active']);"

# Apache 2.4 configuration. NameVirtualHost/httpd are intentionally not used.
cat > /etc/apache2/sites-available/xcs.conf <<APACHE
Listen ${PANEL_PORT}

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
apache2ctl configtest
systemctl reload apache2

# Laravel needs write access only to storage and bootstrap/cache.
chown -R www-data:www-data "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"
chmod -R ug+rwX "${APP_ROOT}/storage" "${APP_ROOT}/bootstrap/cache"

# Use a dedicated cron entry; never erase the root user's existing crontab.
CRON_LINE="* * * * * cd ${APP_ROOT} && php artisan schedule:run >> /dev/null 2>&1"
( crontab -l 2>/dev/null | grep -Fv "${APP_ROOT} && php artisan schedule:run" || true; echo "${CRON_LINE}" ) | crontab -

rm -f /var/www/html/update.zip
php artisan optimize:clear

cat <<EOF

************ Xcs Ubuntu 24 ************
Xcs Link : http://${PANEL_HOST}:${PANEL_PORT}/login
Username : ${ADMIN_USERNAME}
Password : ${ADMIN_PASSWORD}

Installation completed successfully.
EOF
