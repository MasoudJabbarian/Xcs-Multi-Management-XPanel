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

path = Path(sys.argv[1])
text = path.read_text()

old = """        'web' => [\n            'driver' => 'session',\n            'provider' => 'users',\n        ],"""
new = """        'web' => [\n            'driver' => 'session',\n            'provider' => 'admins',\n        ],"""

if old in text:
    text = text.replace(old, new, 1)

path.write_text(text)
PY

python3 - "${USER_CONTROLLER}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# The Users filter reads GET parameters, so Request must be present in index().
text, count = re.subn(
    r'public function index\(\)\s*\{',
    'public function index(Request $request)\n    {',
    text,
    count=1,
)
if count != 1:
    raise SystemExit('Could not patch UserController::index() signature.')

# Bulk delete must be safe when no checkbox was selected.
text = text.replace(
    'foreach ($request->usernamed as $username) {',
    'foreach ((array) $request->input(\'usernamed\', []) as $username) {',
)

path.write_text(text)
PY

php -l "${AUTH_CONFIG}"
php -l "${USER_CONTROLLER}"
