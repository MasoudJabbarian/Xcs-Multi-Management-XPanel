#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${1:-/var/www/html/app}"

if [[ ! -f "${APP_ROOT}/artisan" ]]; then
    echo "Laravel application not found at ${APP_ROOT}." >&2
    exit 1
fi

cd "${APP_ROOT}"

# Laravel public entrypoint used by the Apache DocumentRoot.
mkdir -p public
cat > public/index.php <<'PHP'
<?php

use Illuminate\Contracts\Http\Kernel;
use Illuminate\Http\Request;

define('LARAVEL_START', microtime(true));

if (file_exists($maintenance = __DIR__.'/../storage/framework/maintenance.php')) {
    require $maintenance;
}

require __DIR__.'/../vendor/autoload.php';

$app = require_once __DIR__.'/../bootstrap/app.php';

$kernel = $app->make(Kernel::class);

$response = $kernel->handle(
    $request = Request::capture()
);

$response->send();

$kernel->terminate($request, $response);
PHP

cat > public/.htaccess <<'HTACCESS'
<IfModule mod_rewrite.c>
    RewriteEngine On

    RewriteCond %{REQUEST_FILENAME} !-d
    RewriteCond %{REQUEST_FILENAME} !-f
    RewriteRule ^ index.php [L]
</IfModule>
HTACCESS

# The original project stores the panel assets under Web Panel/cp/assets.
# Copy them into Laravel's public directory so a fresh installation has the
# same working frontend as the validated production installation.
if [[ -d "../cp/assets" ]]; then
    rm -rf public/assets
    cp -a ../cp/assets public/assets
fi

# Unlimited package duration: day=0 means no expiration date.
python3 - "${APP_ROOT}/app/Http/Controllers/UserController.php" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_finish = '''$finishdate = date('Y-m-d', strtotime($start_inp . " + $day days"));'''
new_finish = '''$finishdate = ((int) $day === 0)
                    ? null
                    : date('Y-m-d', strtotime($start_inp . " + $day days"));'''

if old_finish in text:
    text = text.replace(old_finish, new_finish)

old_newdate = '''$newdate = date('Y-m-d', strtotime($newdate . " + $day days"));'''
new_newdate = '''$newdate = ((int) $day === 0)
                        ? null
                        : date('Y-m-d', strtotime($newdate . " + $day days"));'''

if old_newdate in text:
    text = text.replace(old_newdate, new_newdate)

path.write_text(text)
PY

# Synchronize remote users whenever the users page is opened. The remote API
# is considered authoritative only after a successful response. Timeouts or
# HTTP failures never delete local users.
python3 - "${APP_ROOT}/app/Http/Controllers/UserController.php" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

needle = '''        $user = Auth::user();\n        $password_auto = Str::random(8);'''
replacement = '''        $user = Auth::user();\n        $this->syncAllServers();\n        $password_auto = Str::random(8);'''

if needle in text and '$this->syncAllServers();' not in text:
    text = text.replace(needle, replacement, 1)

marker = '''\n}\n'''

methods = r'''

    /**
     * Synchronize users from every configured remote Xcs server.
     *
     * A server is changed only after its API returns a valid JSON user list.
     * Network failures and HTTP errors therefore cannot cause accidental
     * deletion of local users.
     */
    private function syncAllServers(): void
    {
        $servers = Servers::orderBy('id')->get();

        foreach ($servers as $server) {
            $token = trim((string) $server->token);
            $base = rtrim((string) $server->link, '/');

            if ($token === '' || $base === '') {
                continue;
            }

            $remoteUsers = $this->fetchUsersFromServer($base, $token);

            if ($remoteUsers === null) {
                \Illuminate\Support\Facades\Log::warning('XCS user sync skipped server because API failed', [
                    'server_id' => $server->id,
                    'server' => $server->name ?? null,
                    'link' => $base,
                ]);
                continue;
            }

            $seen = [];
            $created = 0;
            $updated = 0;

            foreach ($remoteUsers as $remote) {
                if (!is_array($remote)) {
                    continue;
                }

                $username = trim((string) ($remote['username'] ?? ''));
                if ($username === '') {
                    continue;
                }

                $seen[] = $username;

                $local = Users::where('server', (string) $server->id)
                    ->where('username', $username)
                    ->first();

                $values = [
                    'server' => (string) $server->id,
                    'username' => $username,
                    'password' => (string) ($remote['password'] ?? ($local?->password ?? '')),
                    'email' => $remote['email'] ?? ($local?->email),
                    'mobile' => $remote['mobile'] ?? ($local?->mobile),
                    'multiuser' => (string) ($remote['multiuser'] ?? ($local?->multiuser ?? 1)),
                    'start_date' => $remote['start_date'] ?? ($local?->start_date),
                    'end_date' => $remote['end_date'] ?? ($local?->end_date),
                    'date_one_connect' => $remote['date_one_connect'] ?? ($local?->date_one_connect ?? '0'),
                    'customer_user' => $local?->customer_user ?: 'API',
                    'status' => (string) ($remote['status'] ?? ($local?->status ?? 'active')),
                    'traffic' => (string) ($remote['traffic'] ?? ($local?->traffic ?? '0')),
                    'package' => (string) ($local?->package ?? ''),
                    'desc' => $remote['desc'] ?? ($local?->desc),
                ];

                Users::updateOrCreate(
                    [
                        'server' => (string) $server->id,
                        'username' => $username,
                    ],
                    $values
                );

                if ($local) {
                    $updated++;
                } else {
                    $created++;
                }

                $remoteTraffic = $remote['traffics'][0] ?? null;
                if (is_array($remoteTraffic)) {
                    Traffic::updateOrCreate(
                        ['username' => $username],
                        [
                            'download' => (string) ($remoteTraffic['download'] ?? 0),
                            'upload' => (string) ($remoteTraffic['upload'] ?? 0),
                            'total' => (string) ($remoteTraffic['total'] ?? 0),
                        ]
                    );
                } else {
                    Traffic::firstOrCreate(
                        ['username' => $username],
                        [
                            'download' => '0',
                            'upload' => '0',
                            'total' => '0',
                        ]
                    );
                }
            }

            $staleQuery = Users::where('server', (string) $server->id);

            if ($seen) {
                $staleQuery->whereNotIn('username', array_values(array_unique($seen)));
            }

            $staleUsers = $staleQuery->get(['username']);

            foreach ($staleUsers as $stale) {
                Users::where('server', (string) $server->id)
                    ->where('username', $stale->username)
                    ->delete();
                Traffic::where('username', $stale->username)->delete();
            }

            \Illuminate\Support\Facades\Log::info('XCS user sync completed', [
                'server_id' => $server->id,
                'fetched' => count($remoteUsers),
                'created' => $created,
                'updated' => $updated,
                'deleted' => $staleUsers->count(),
            ]);
        }
    }

    private function fetchUsersFromServer(string $base, string $token): ?array
    {
        try {
            $response = \Illuminate\Support\Facades\Http::connectTimeout(5)
                ->timeout(15)
                ->acceptJson()
                ->get($base . '/api/' . rawurlencode($token) . '/listuser');

            if (!$response->successful()) {
                return null;
            }

            $json = $response->json();
            if (!is_array($json)) {
                return null;
            }

            if (array_is_list($json)) {
                return $json;
            }

            if (isset($json['users']) && is_array($json['users'])) {
                return $json['users'];
            }

            if (isset($json['data']) && is_array($json['data'])) {
                if (isset($json['data']['users']) && is_array($json['data']['users'])) {
                    return $json['data']['users'];
                }

                if (array_is_list($json['data'])) {
                    return $json['data'];
                }
            }
        } catch (\Throwable $e) {
            return null;
        }

        return null;
    }
'''

# Insert before the final class closing brace.
if 'private function syncAllServers()' not in text:
    pos = text.rfind('\n}')
    if pos == -1:
        raise SystemExit('Could not find UserController class closing brace')
    text = text[:pos] + methods + text[pos:]

path.write_text(text)
PY

# Keep the application files owned by the web server after installation.
chown -R www-data:www-data "${APP_ROOT}/public"
find "${APP_ROOT}/public" -type d -exec chmod 755 {} \;
find "${APP_ROOT}/public" -type f -exec chmod 644 {} \;

# Validate the patched controller before allowing installation to continue.
php -l "${APP_ROOT}/app/Http/Controllers/UserController.php"
php -l "${APP_ROOT}/app/Http/Controllers/ApiController.php"
php -l "${APP_ROOT}/app/Http/Controllers/PackagesController.php"
php -l "${APP_ROOT}/routes/web.php"
