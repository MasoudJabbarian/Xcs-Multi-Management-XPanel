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

old = '''        if($user->permission=='admin')
        {
            $users = Users::orderBy('id', 'desc')->get();
        }
        else{
            $users = Users::where('customer_user', $user->username)->orderby('id', 'desc')->get();
        }
        $settings = Settings::all();'''

new = '''        $selectedServers = $request->input('servers', []);
        if (!is_array($selectedServers)) {
            $selectedServers = [$selectedServers];
        }
        $selectedServers = array_values(array_filter($selectedServers, static fn ($id) => ctype_digit((string) $id)));
        $statusFilter = (string) $request->input('status', 'all');
        $searchFilter = trim((string) $request->input('search', ''));
        $packageFilter = (string) $request->input('package', 'all');

        $userQuery = Users::query();

        if ($user->permission != 'admin') {
            $userQuery->where('customer_user', $user->username);
        }

        if (!empty($selectedServers)) {
            $userQuery->whereIn('server', $selectedServers);
        }

        switch ($statusFilter) {
            case 'active':
                $userQuery->whereIn('status', ['active', 'true']);
                break;
            case 'deactive':
                $userQuery->whereIn('status', ['deactive', 'false']);
                break;
            case 'expired':
                $userQuery->where('status', 'expired');
                break;
            case 'traffic':
                $userQuery->where('status', 'traffic');
                break;
            case 'expiring7':
                $userQuery->whereNotNull('end_date')
                    ->where('end_date', '!=', '')
                    ->where('end_date', '!=', 'NULL')
                    ->whereBetween('end_date', [date('Y-m-d'), date('Y-m-d', strtotime('+7 days'))]);
                break;
        }

        if ($packageFilter !== 'all' && ctype_digit($packageFilter)) {
            $userQuery->where('package', $packageFilter);
        }

        if ($searchFilter !== '') {
            $userQuery->where(function ($query) use ($searchFilter) {
                $query->where('username', 'like', '%' . $searchFilter . '%')
                    ->orWhere('customer_user', 'like', '%' . $searchFilter . '%')
                    ->orWhere('email', 'like', '%' . $searchFilter . '%')
                    ->orWhere('mobile', 'like', '%' . $searchFilter . '%');
            });
        }

        $users = $userQuery->orderBy('id', 'desc')->get();
        $settings = Settings::all();'''

if old in text:
    text = text.replace(old, new, 1)
else:
    # Already patched: verify the expected filter query exists and leave it intact.
    required = [
        "$selectedServers = $request->input('servers', []);",
        "$userQuery->whereIn('server', $selectedServers);",
        "$statusFilter = (string) $request->input('status', 'all');",
        "$packageFilter = (string) $request->input('package', 'all');",
    ]
    missing = [item for item in required if item not in text]
    if missing:
        raise SystemExit('UserController filter query block not found; no changes made.')

path.write_text(text)
PY

python3 - "${USERS_VIEW}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

# Remove an older filter block if this installer was previously run. The old
# version placed a GET form inside the bulk-delete POST form, which makes the
# browser submit to user.delete.bulk when Filter is clicked.
start_marker = '<div class="p-4 pb-2">'
end_marker = '                                <div class="text-end p-4 pb-0">'
start = text.find(start_marker)
if start != -1:
    candidate_end = text.find(end_marker, start)
    candidate = text[start:candidate_end] if candidate_end != -1 else ''
    if 'id="filter-status"' in candidate and 'name="servers[]"' in candidate:
        text = text[:start] + text[candidate_end:]

filter_block = r'''                                <!-- XCS_USER_FILTERS_START -->
                                <div class="p-4 pb-2">
                                    <form method="GET" action="{{ route('users') }}">
                                        <div class="row g-3 align-items-end">
                                            <div class="col-lg-4 col-md-6">
                                                <label class="form-label fw-bold">Server Filter</label>
                                                <div class="border rounded p-2" style="max-height: 130px; overflow-y: auto;">
                                                    @php
                                                        $selectedFilterServers = array_map('strval', (array) request('servers', []));
                                                    @endphp
                                                    @forelse($servers as $filterServer)
                                                        <div class="form-check">
                                                            <input class="form-check-input" type="checkbox" name="servers[]"
                                                                   value="{{ $filterServer->id }}" id="filter-server-{{ $filterServer->id }}"
                                                                   {{ in_array((string) $filterServer->id, $selectedFilterServers, true) ? 'checked' : '' }}>
                                                            <label class="form-check-label" for="filter-server-{{ $filterServer->id }}">
                                                                {{ $filterServer->name }}
                                                            </label>
                                                        </div>
                                                    @empty
                                                        <small class="text-muted">No servers configured.</small>
                                                    @endforelse
                                                </div>
                                                <small class="text-muted">Select one or several servers. Leave all unchecked to show all servers.</small>
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
                                                    <option value="all" {{ request('package', 'all') === 'all' ? 'selected' : '' }}>All Packages</option>
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
                                <!-- XCS_USER_FILTERS_END -->

'''

# Insert the filter form BEFORE the bulk-delete form, never inside it.
delete_form_marker = '                                <form action="{{route(\'user.delete.bulk\')}}" method="post" enctype="multipart/form-data">'
if delete_form_marker not in text:
    # Handle the same source with whitespace differences.
    delete_form_marker = '                                <form action="{{route(\'user.delete.bulk\')}}"'

if delete_form_marker not in text:
    raise SystemExit('Bulk delete form marker not found in users view.')

if '<!-- XCS_USER_FILTERS_START -->' not in text:
    text = text.replace(delete_form_marker, filter_block + delete_form_marker, 1)
else:
    # If a tagged block already exists, ensure it is before the delete form.
    tagged_start = text.find('                                <!-- XCS_USER_FILTERS_START -->')
    tagged_end = text.find('                                <!-- XCS_USER_FILTERS_END -->', tagged_start)
    if tagged_end == -1:
        raise SystemExit('Incomplete XCS filter block.')
    tagged_end = text.find('\n', tagged_end) + 1
    block = text[tagged_start:tagged_end]
    text = text[:tagged_start] + text[tagged_end:]
    delete_pos = text.find(delete_form_marker)
    if delete_pos == -1:
        raise SystemExit('Bulk delete form marker not found after filter cleanup.')
    text = text[:delete_pos] + block + '\n' + text[delete_pos:]

path.write_text(text)
PY

php -l "${USER_CONTROLLER}"
