#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${1:-/var/www/html/app}"
AUTH_CONFIG="${APP_ROOT}/config/auth.php"
USER_CONTROLLER="${APP_ROOT}/app/Http/Controllers/UserController.php"

[[ -f "${AUTH_CONFIG}" ]] || { echo "auth.php not found." >&2; exit 1; }
[[ -f "${USER_CONTROLLER}" ]] || { echo "UserController.php not found." >&2; exit 1; }

python3 - "${AUTH_CONFIG}" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text()
t=t.replace("'provider' => 'users',", "'provider' => 'admins',", 1)
p.write_text(t)
PY

python3 - "${USER_CONTROLLER}" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); t=p.read_text()
# Accept both the original index() and a previously patched index(Request $request).
if re.search(r'public function index\(\s*\)', t):
    t=re.sub(r'public function index\(\s*\)', 'public function index(Request $request)', t, count=1)
elif not re.search(r'public function index\(\s*Request\s+\$request\s*\)', t):
    raise SystemExit('Could not locate UserController::index() signature.')
t=t.replace("foreach ($request->usernamed as $username) {", "foreach ((array) $request->input('usernamed', []) as $username) {")
p.write_text(t)
PY

php -l "${AUTH_CONFIG}"
php -l "${USER_CONTROLLER}"
echo 'XCS hardening completed successfully.'
