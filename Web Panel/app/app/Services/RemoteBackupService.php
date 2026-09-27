<?php

namespace App\Services;

use App\Models\RemoteBackup;
use App\Models\Servers;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Log;
use RuntimeException;

class RemoteBackupService
{
    public const RETENTION = 15;

    public function createRemoteBackup(Servers $server): RemoteBackup
    {
        $token = trim((string) $server->token);
        $base = rtrim((string) $server->link, '/');

        if ($token === '' || $base === '') {
            throw new RuntimeException('Server API link or token is empty.');
        }

        $directory = storage_path('app/server-backups/' . $server->id);
        if (!is_dir($directory) && !mkdir($directory, 0775, true) && !is_dir($directory)) {
            throw new RuntimeException('Unable to create management backup directory.');
        }

        $filename = 'Xcs-Remote-' . now()->format('Y-m-d---H-i-s') . '.sql';
        $target = $directory . '/' . $filename;

        $fp = fopen($target, 'wb');
        if ($fp === false) {
            throw new RuntimeException('Unable to create management backup file.');
        }

        try {
            $ch = curl_init($base . '/api/backup');
            if ($ch === false) {
                throw new RuntimeException('Unable to initialize backup request.');
            }

            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => false,
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => http_build_query(['token' => $token]),
                CURLOPT_CONNECTTIMEOUT => 10,
                CURLOPT_TIMEOUT => 300,
                CURLOPT_FOLLOWLOCATION => false,
                CURLOPT_WRITEFUNCTION => static function ($ch, $data) use ($fp) {
                    return fwrite($fp, $data);
                },
                CURLOPT_HEADERFUNCTION => static function ($ch, $header) use (&$remoteFilename) {
                    $length = strlen($header);
                    $trimmed = trim($header);
                    if (stripos($trimmed, 'X-Xcs-Backup-Name:') === 0) {
                        $remoteFilename = trim(substr($trimmed, strlen('X-Xcs-Backup-Name:')));
                    }
                    return $length;
                },
            ]);

            $ok = curl_exec($ch);
            $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $contentType = (string) curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
            $curlError = curl_error($ch);
            curl_close($ch);

            fflush($fp);
            fclose($fp);

            if (!$ok || $httpCode < 200 || $httpCode >= 300) {
                @unlink($target);
                $message = $curlError !== '' ? $curlError : 'Remote backup API returned HTTP ' . $httpCode . '.';
                throw new RuntimeException($message);
            }

            $size = (int) filesize($target);
            if ($size < 1) {
                @unlink($target);
                throw new RuntimeException('Remote backup response was empty.');
            }

            if ($contentType !== '' && stripos($contentType, 'application/sql') === false && stripos($contentType, 'application/octet-stream') === false && stripos($contentType, 'text/plain') === false) {
                Log::warning('Remote backup returned an unexpected content type.', [
                    'server_id' => $server->id,
                    'content_type' => $contentType,
                ]);
            }

            $backup = RemoteBackup::create([
                'server_id' => $server->id,
                'filename' => $remoteFilename ?? $filename,
                'path' => 'server-backups/' . $server->id . '/' . $filename,
                'taken_at' => now(),
                'size' => $size,
                'status' => 'success',
            ]);

            $this->enforceRetention($server->id);

            return $backup;
        } catch (\Throwable $e) {
            if (is_resource($fp)) {
                fclose($fp);
            }
            @unlink($target);
            throw $e;
        }
    }

    public function enforceRetention(int $serverId): void
    {
        $old = RemoteBackup::where('server_id', $serverId)
            ->where('status', 'success')
            ->orderByDesc('taken_at')
            ->orderByDesc('id')
            ->skip(self::RETENTION)
            ->take(1000)
            ->get();

        foreach ($old as $backup) {
            Storage::delete($backup->path);
            $backup->delete();
        }
    }
}
