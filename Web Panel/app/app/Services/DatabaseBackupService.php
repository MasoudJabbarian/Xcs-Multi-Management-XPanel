<?php

namespace App\Services;

use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Storage;
use RuntimeException;

class DatabaseBackupService
{
    public function create(string $prefix = 'Xcs'): string
    {
        $date = now()->format('Y-m-d---H-i-s');
        $filename = $prefix . '-' . $date . '.sql';

        $result = Process::env(['MYSQL_PWD' => (string) env('DB_PASSWORD')])
            ->timeout(300)
            ->run([
                'mysqldump',
                '--single-transaction',
                '--quick',
                '-u',
                (string) env('DB_USERNAME'),
                (string) env('DB_DATABASE', 'Xcs'),
            ]);

        if (!$result->successful()) {
            throw new RuntimeException('Database backup failed: ' . trim($result->errorOutput()));
        }

        if (trim($result->output()) === '') {
            throw new RuntimeException('Database backup produced an empty file.');
        }

        Storage::put('backup/' . $filename, $result->output());

        return $filename;
    }

    public function cleanupRemoteBackups(int $keep = 15): void
    {
        $files = collect(Storage::files('backup'))
            ->filter(fn ($path) => str_starts_with(basename($path), 'Xcs-Remote-'))
            ->sortDesc()
            ->values();

        foreach ($files->slice($keep) as $path) {
            Storage::delete($path);
        }
    }
}
