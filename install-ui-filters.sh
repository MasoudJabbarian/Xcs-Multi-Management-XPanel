#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="${1:-/var/www/html/app}"
USER_CONTROLLER="${APP_ROOT}/app/Http/Controllers/UserController.php"
USERS_VIEW="${APP_ROOT}/resources/views/users/home.blade.php"

[[ -f "${USER_CONTROLLER}" ]] || { echo "UserController.php not found." >&2; exit 1; }
[[ -f "${USERS_VIEW}" ]] || { echo "Users view not found." >&2; exit 1; }

python3 - "${USER_CONTROLLER}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = '''        if($user->permission=='admin')\n        {\n            $users = Users::orderBy('id', 'desc')->get();\n        }\n        else{\n            $users = Users::where('customer_user', $user->username)->orderby('id', 'desc')->get();\n        }\n        $settings = Settings::all();'''

new = '''        $selectedServers = $request->input('servers', []);\n        if (!is_array($selectedServers)) {\n            $selectedServers = [$selectedServers];\n        }\n        $selectedServers = array_values(array_filter($selectedServers, static fn ($id) => ctype_digit((string) $id)));\n        $statusFilter = (string) $request->input('status', 'all');\n        $searchFilter = trim((string) $request->input('search', ''));\n        $packageFilter = (string) $request->input('package', 'all');\n\n        $userQuery = Users::query();\n\n        if ($user->permission != 'admin') {\n            $userQuery->where('customer_user', $user->username);\n        }\n\n        if (!empty($selectedServers)) {\n            $userQuery->whereIn('server', $selectedServers);\n        }\n\n        switch ($statusFilter) {\n            case 'active':\n                $userQuery->whereIn('status', ['active', 'true']);\n                break;\n            case 'deactive':\n                $userQuery->whereIn('status', ['deactive', 'false']);\n                break;\n            case 'expired':\n                $userQuery->where('status', 'expired');\n                break;\n            case 'traffic':\n                $userQuery->where('status', 'traffic');\n                break;\n            case 'expiring7':\n                $userQuery->whereNotNull('end_date')\n                    ->where('end_date', '!=', '')\n                    ->where('end_date', '!=', 'NULL')\n                    ->whereBetween('end_date', [date('Y-m-d'), date('Y-m-d', strtotime('+7 days'))]);\n                break;\n        }\n\n        if ($packageFilter !== 'all' && ctype_digit($packageFilter)) {\n            $userQuery->where('package', $packageFilter);\n        }\n\n        if ($searchFilter !== '') {\n            $userQuery->where(function ($query) use ($searchFilter) {\n                $query->where('username', 'like', '%' . $searchFilter . '%')\n                    ->orWhere('customer_user', 'like', '%' . $searchFilter . '%')\n                    ->orWhere('email', 'like', '%' . $searchFilter . '%')\n                    ->orWhere('mobile', 'like', '%' . $searchFilter . '%');\n            });\n        }\n\n        $users = $userQuery->orderBy('id', 'desc')->get();\n        $settings = Settings::all();'''

if old not in text:
    raise SystemExit('UserController index query block not found; no changes made.')

text = text.replace(old, new, 1)
path.write_text(text)
PY

python3 - "${USERS_VIEW}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

marker = '''                                <div class="text-end p-4 pb-0">'''
filters = r'''                                <div class="p-4 pb-2">
                                    <form method="GET" action="{{ route('users') }}">
                                        <div class="row g-3 align-items-end">
                                            <div class="col-lg-4 col-md-6">
                                                <label class="form-label fw-bold">Server Filter</label>
                                                <div class="border rounded p-2" style="max-height: 130px; overflow-y: auto;">
                                                    @forelse($servers as $filterServer)
                                                        <div class="form-check">
                                                            <input class="form-check-input" type="checkbox" name="servers[]"
                                                                   value="{{ $filterServer->id }}" id="filter-server-{{ $filterServer->id }}"
                                                                   {{ in_array((string) $filterServer->id, array_map('strval', request('servers', []))) ? 'checked' : '' }}>
                                                            <label class="form-check-label" for="filter-server-{{ $filterServer->id }}">
                                                                {{ $filterServer->name }}
                                                            </label>
                                                        </div>
                                                    @empty
                                                        <small class="text-muted">No servers configured.</small>
                                                    @endforelse
                                                </div>
                                                <small class="text-muted">Select one, several, or leave all unchecked for all servers.</small>
                                            </div>

                                            <div class="col-lg-2 col-md-6">
                                                <label for="filter-status" class="form-label fw-bold">Status Filter</label>
                                                <select class="form-select" id="filter-status" name="status">
                                                    <option value="all" {{ request('status', 'all') === 'all' ? 'selected' : '' }}>All</option>
                                                    <option value="active" {{ request('status') === 'active' ? 'selected' : '' }}>Active</option>
                                                    <option value="deactive" {{ request('status') === 'deactive' ? 'selected' : '' }}>Deactive</option>
                                                    <option value="expired" {{ request('status') === 'expired' ? 'selected' : '' }}>Expired</option>
                                                    <option value="traffic" {{ request('status') === 'traffic' ? 'selected' : '' }}>Traffic Limit</option>
                                                    <option value="expiring7" {{ request('status') === 'expiring7' ? 'selected' : '' }}>Expires in 7 Days</option>
                                                </select>
                                            </div>

                                            <div class="col-lg-2 col-md-6">
                                                <label for="filter-package" class="form-label fw-bold">Package Filter</label>
                                                <select class="form-select" id="filter-package" name="package">
                                                    <option value="all">All Packages</option>
                                                    @foreach($packages as $filterPackage)
                                                        <option value="{{ $filterPackage->id }}" {{ (string) request('package', 'all') === (string) $filterPackage->id ? 'selected' : '' }}>
                                                            {{ $filterPackage->title }}
                                                        </option>
                                                    @endforeach
                                                </select>
                                            </div>

                                            <div class="col-lg-3 col-md-6">
                                                <label for="filter-search" class="form-label fw-bold">Search User</label>
                                                <input type="text" class="form-control" id="filter-search" name="search"
                                                       value="{{ request('search') }}"
                                                       placeholder="Username, customer, email, mobile">
                                            </div>

                                            <div class="col-lg-1 col-md-6 d-grid">
                                                <button type="submit" class="btn btn-primary">Filter</button>
                                            </div>
                                        </div>
                                        <div class="mt-2">
                                            <a href="{{ route('users') }}" class="btn btn-light btn-sm">Reset Filters</a>
                                            <span class="text-muted ms-2">{{ $users->count() }} users matched</span>
                                        </div>
                                    </form>
                                </div>

'''

if 'id="filter-status"' not in text:
    if marker not in text:
        raise SystemExit('Users view filter insertion marker not found.')
    text = text.replace(marker, filters + marker, 1)

path.write_text(text)
PY

php -l "${USER_CONTROLLER}"
