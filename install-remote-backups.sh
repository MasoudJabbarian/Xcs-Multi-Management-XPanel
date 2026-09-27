#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${1:-/var/www/html/app}"
REPO="MasoudJabbarian/Xcs-Multi-Management-XPanel"
BRANCH="ubuntu-24-support"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/xcs-remote-backups-preinstall-${STAMP}"

if [[ ${EUID} -ne 0 ]]; then
    echo "Please run as root." >&2
    exit 1
fi

[[ -f "${APP_ROOT}/artisan" ]] || {
    echo "Laravel application not found at ${APP_ROOT}." >&2
    exit 1
}

mkdir -p "${BACKUP_DIR}"

declare -a FILES=(
    "Web Panel/app/app/Models/RemoteBackup.php"
    "Web Panel/app/app/Models/Settings.php"
    "Web Panel/app/app/Services/DatabaseBackupService.php"
    "Web Panel/app/app/Services/RemoteBackupService.php"
    "Web Panel/app/app/Console/Commands/RemoteBackups.php"
    "Web Panel/app/app/Http/Controllers/ApiController.php"
    "Web Panel/app/app/Http/Controllers/SettingsController.php"
    "Web Panel/app/database/migrations/2026_09_27_000001_create_remote_backups_table.php"
    "Web Panel/app/database/migrations/2026_09_27_000002_add_remote_backup_settings_to_settings_table.php"
    "Web Panel/app/resources/views/settings/backup.blade.php"
    "Web Panel/app/resources/views/settings/index.blade.php"
    "Web Panel/app/routes/api.php"
    "Web Panel/app/routes/web.php"
)

for repo_path in "${FILES[@]}"; do
    relative="${repo_path#Web Panel/app/}"
    target="${APP_ROOT}/${relative}"
    mkdir -p "$(dirname "${target}")"

    if [[ -f "${target}" ]]; then
        cp -a "${target}" "${BACKUP_DIR}/$(basename "${target}").old"
    fi

    tmp="$(mktemp)"
    curl -fsSL "${RAW_BASE}/${repo_path// /%20}" -o "${tmp}"
    install -m 0644 "${tmp}" "${target}"
    rm -f "${tmp}"
done

cd "${APP_ROOT}"

mkdir -p storage/app/server-backups storage/logs
chown -R www-data:www-data storage
chmod -R ug+rwX storage

php -l app/Models/RemoteBackup.php
php -l app/Models/Settings.php
php -l app/Services/DatabaseBackupService.php
php -l app/Services/RemoteBackupService.php
php -l app/Console/Commands/RemoteBackups.php
php -l app/Http/Controllers/ApiController.php
php -l app/Http/Controllers/SettingsController.php
php -l routes/api.php
php -l routes/web.php

composer dump-autoload --no-interaction
php artisan migrate --force

CRON_MARKER="# XCS_REMOTE_BACKUPS"
CRON_LINE="* * * * * cd ${APP_ROOT} && /usr/bin/runuser -u www-data -- /usr/bin/php artisan xcs:remote-backups >> ${APP_ROOT}/storage/logs/remote-backups-cron.log 2>&1 ${CRON_MARKER}"
( crontab -l 2>/dev/null | grep -Fv "${CRON_MARKER}" || true; echo "${CRON_LINE}" ) | crontab -

php artisan optimize:clear
php artisan config:cache

echo
echo "XCS remote backup feature installed successfully."
echo "App      : ${APP_ROOT}"
echo "Cron     : every minute (the command runs only at configured backup times)"
echo "Retention: 15 successful backups per remote server"
echo "Previous : ${BACKUP_DIR}"
