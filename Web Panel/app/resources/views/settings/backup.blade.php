@extends('layouts.master')
@section('title','Xcs - Settings')
@section('content')
    @if(!empty(session('success')))
        <div class="p-4 mb-2" style="position: fixed;z-index: 9999;left: 0;">
            <div class="toast fade show" role="alert" aria-live="assertive" aria-atomic="true">
                <div class="toast-header">
                    <img src="/assets/images/xlogo.png" class="img-fluid m-r-5" alt="Xcs" style="width: 17px">
                    <strong class="me-auto">Xcs</strong>
                    <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
                </div>
                <div class="toast-body">{{ session('success') }}</div>
            </div>
        </div>
    @endif

    @if(!empty(session('error')))
        <div class="p-4 mb-2" style="position: fixed;z-index: 9999;left: 0;">
            <div class="toast fade show" role="alert" aria-live="assertive" aria-atomic="true">
                <div class="toast-header">
                    <img src="/assets/images/xlogo.png" class="img-fluid m-r-5" alt="Xcs" style="width: 17px">
                    <strong class="me-auto">Xcs</strong>
                    <button type="button" class="btn-close" data-bs-dismiss="toast" aria-label="Close"></button>
                </div>
                <div class="toast-body"><span style="color:red">{{ session('error') }}</span></div>
            </div>
        </div>
    @endif

    <div class="pc-container">
        <div class="pc-content">
            <div class="page-header">
                <div class="page-block">
                    <div class="row align-items-center">
                        <div class="col-md-12">
                            <div class="page-header-title">
                                <h2 class="mb-0">Settings - Backup</h2>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="row">
                <div class="col-sm-12">
                    <div class="card">
                        @include('layouts.setting_menu')
                        <div class="tab-content" id="myTabContent">
                            <div class="card-body">

                                <div class="alert alert-info">
                                    <strong>Remote server backups:</strong>
                                    The panel requests a database backup from every configured server through its API,
                                    keeps a copy on that server and transfers another copy to this management server.
                                    The latest 15 successful backups are retained per server.
                                </div>

                                <div class="card mb-4">
                                    <div class="card-header">
                                        <h5 class="mb-0">Automatic Remote Backups</h5>
                                    </div>
                                    <div class="card-body">
                                        <form action="{{ route('settings.backup.schedule') }}" method="post">
                                            @csrf
                                            <div class="row g-3 align-items-end">
                                                <div class="col-lg-2">
                                                    <label class="form-label fw-bold">Enable</label>
                                                    <div class="form-check form-switch">
                                                        <input class="form-check-input" type="checkbox" name="enabled" value="1"
                                                               {{ ($backupSettings?->remote_backup_enabled ?? '0') === '1' ? 'checked' : '' }}>
                                                        <label class="form-check-label">Automatic backup</label>
                                                    </div>
                                                </div>
                                                <div class="col-lg-7">
                                                    <label class="form-label fw-bold">Backup times</label>
                                                    <input type="text" name="times" class="form-control"
                                                           value="{{ $backupSettings?->remote_backup_times ?? '' }}"
                                                           placeholder="02:00, 08:00, 20:00">
                                                    <small class="form-text text-muted">
                                                        Enter one or more 24-hour times separated by comma, space, or semicolon.
                                                        The server's local timezone is used.
                                                    </small>
                                                </div>
                                                <div class="col-lg-2">
                                                    <label class="form-label fw-bold">Retention</label>
                                                    <input type="text" class="form-control" value="15" readonly>
                                                    <small class="form-text text-muted">Per server</small>
                                                </div>
                                                <div class="col-lg-1 d-grid">
                                                    <button type="submit" class="btn btn-primary">Save</button>
                                                </div>
                                            </div>
                                        </form>
                                    </div>
                                </div>

                                <div class="card mb-4">
                                    <div class="card-header d-flex justify-content-between align-items-center">
                                        <h5 class="mb-0">Remote Servers</h5>
                                        <form action="{{ route('settings.backup.remote.all') }}" method="post"
                                              onsubmit="return confirm('Start a backup on every configured server now?');">
                                            @csrf
                                            <button type="submit" class="btn btn-primary">Backup All Servers Now</button>
                                        </form>
                                    </div>
                                    <div class="card-body">
                                        <div class="table-responsive">
                                            <table class="table table-hover">
                                                <thead>
                                                <tr>
                                                    <th>Server</th>
                                                    <th>Backup File</th>
                                                    <th>Backup Time</th>
                                                    <th>Size</th>
                                                    <th>Status</th>
                                                    <th class="text-center">Actions</th>
                                                </tr>
                                                </thead>
                                                <tbody>
                                                @forelse($remoteBackups as $backup)
                                                    <tr>
                                                        <td>{{ $backup->server?->name ?? 'Deleted server' }}</td>
                                                        <td>{{ $backup->filename }}</td>
                                                        <td>{{ optional($backup->taken_at)->format('Y-m-d H:i:s') }}</td>
                                                        <td>{{ number_format($backup->size / 1048576, 2) }} MB</td>
                                                        <td>
                                                            <span class="badge bg-light-success rounded-pill">Success</span>
                                                        </td>
                                                        <td class="text-center">
                                                            <a href="{{ route('settings.backup.remote.download', ['id' => $backup->id]) }}"
                                                               class="avtar avtar-xs btn-link-success btn-pc-default" title="Download">
                                                                <i class="ti ti-download f-18"></i>
                                                            </a>
                                                            <a href="{{ route('settings.backup.remote.delete', ['id' => $backup->id]) }}"
                                                               class="avtar avtar-xs btn-link-danger btn-pc-default"
                                                               title="Delete"
                                                               onclick="return confirm('Delete this management-server copy?');">
                                                                <i class="ti ti-trash f-18"></i>
                                                            </a>
                                                        </td>
                                                    </tr>
                                                @empty
                                                    <tr>
                                                        <td colspan="6" class="text-center text-muted">No remote server backups yet.</td>
                                                    </tr>
                                                @endforelse
                                                </tbody>
                                            </table>
                                        </div>
                                    </div>
                                </div>

                                <div class="card">
                                    <div class="card-header">
                                        <h5 class="mb-0">Management Server Backup</h5>
                                    </div>
                                    <div class="card-body">
                                        <form action="{{ route('settings.backup.make') }}" method="post" class="mb-3">
                                            @csrf
                                            <button type="submit" class="btn btn-secondary">Make Management Server Backup</button>
                                        </form>

                                        <form action="{{ route('settings.backup.upload') }}" method="post" enctype="multipart/form-data">
                                            @csrf
                                            <div class="row align-items-end">
                                                <div class="col-lg-6">
                                                    <label class="form-label">Upload SQL file</label>
                                                    <input class="form-control" type="file" name="file" required>
                                                </div>
                                                <div class="col-lg-2">
                                                    <button type="submit" class="btn btn-secondary">Upload</button>
                                                </div>
                                            </div>
                                        </form>

                                        <hr>

                                        <div class="table-responsive">
                                            <table class="table table-hover">
                                                <thead>
                                                <tr>
                                                    <th>Name</th>
                                                    <th>Time</th>
                                                    <th class="text-center">Actions</th>
                                                </tr>
                                                </thead>
                                                <tbody>
                                                @forelse($lists as $list)
                                                    @php
                                                        $stamp = preg_replace('/^Xcs-/', '', pathinfo($list, PATHINFO_FILENAME));
                                                    @endphp
                                                    <tr>
                                                        <td>{{ $list }}</td>
                                                        <td>{{ $stamp }}</td>
                                                        <td class="text-center">
                                                            <a href="{{ route('settings.backup.dl', ['name' => $list]) }}"
                                                               class="avtar avtar-xs btn-link-success btn-pc-default" title="Download">
                                                                <i class="ti ti-download f-18"></i>
                                                            </a>
                                                            <a href="{{ route('settings.backup.restore', ['name' => $list]) }}"
                                                               class="avtar avtar-xs btn-link-warning btn-pc-default"
                                                               title="Restore"
                                                               onclick="return confirm('Restore this backup?');">
                                                                <i class="ti ti-refresh f-18"></i>
                                                            </a>
                                                            <a href="{{ route('settings.backup.delete', ['name' => $list]) }}"
                                                               class="avtar avtar-xs btn-link-danger btn-pc-default"
                                                               title="Delete"
                                                               onclick="return confirm('Delete this backup?');">
                                                                <i class="ti ti-trash f-18"></i>
                                                            </a>
                                                        </td>
                                                    </tr>
                                                @empty
                                                    <tr>
                                                        <td colspan="3" class="text-center text-muted">No management server backups.</td>
                                                    </tr>
                                                @endforelse
                                                </tbody>
                                            </table>
                                        </div>
                                    </div>
                                </div>

                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
@endsection
