<?php

namespace App\Console\Commands;

use App\Models\RemoteBackup;
use App\Models\Servers;
use App\Models\Settings;
use App\Services\RemoteBackupService;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Log;

class RemoteBackups extends Command
{
    protected $signature = 'xcs:remote-backups';
    protected $description = 'Create scheduled backups for all configured remote Xcs servers.';

    public function handle(RemoteBackupService $backupService): int
    {
        $settings = Settings::first();
        $enabled = $settings?->remote_backup_enabled === '1';
        $times = (string) ($settings?->remote_backup_times ?? '');

        if (!$enabled) {
            return self::SUCCESS;
        }

        $now = now();
        $current = $now->format('H:i');
        $configured = collect(preg_split('/[\s,;]+/', $times))
            ->map(fn ($time) => trim($time))
            ->filter(fn ($time) => preg_match('/^([01]\d|2[0-3]):[0-5]\d$/', $time))
            ->unique()
            ->values();

        if (!$configured->contains($current)) {
            return self::SUCCESS;
        }

        $lockPath = storage_path('app/remote-backup-' . $now->format('Y-m-d-H-i') . '.lock');
        $lock = @fopen($lockPath, 'x');
        if ($lock === false) {
            return self::SUCCESS;
        }

        try {
            foreach (Servers::orderBy('id')->get() as $server) {
                try {
                    $backupService->createRemoteBackup($server);
                    $this->info('Backup completed: ' . $server->name);
                } catch (\Throwable $e) {
                    RemoteBackup::create([
                        'server_id' => $server->id,
                        'filename' => 'FAILED-' . $now->format('Y-m-d---H-i-s') . '.log',
                        'path' => '',
                        'taken_at' => $now,
                        'size' => 0,
                        'status' => 'failed',
                        'error' => $e->getMessage(),
                    ]);
                    Log::error('Scheduled remote backup failed.', [
                        'server_id' => $server->id,
                        'server' => $server->name,
                        'error' => $e->getMessage(),
                    ]);
                    $this->error('Backup failed: ' . $server->name . ' - ' . $e->getMessage());
                }
            }
        } finally {
            fclose($lock);
            @unlink($lockPath);
        }

        return self::SUCCESS;
    }
}
