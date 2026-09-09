<?php

namespace App\Http\Controllers;

use App\Models\Servers;
use App\Models\Traffic;
use App\Models\Users;
use Illuminate\Support\Facades\Auth;

class DahboardController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth:admins');
    }

    private function check(): void
    {
        if (Auth::guard('admins')->user()?->permission === 'reseller') {
            redirect()->route('users')->send();
        }
    }

    private function onlineUsers(): array
    {
        $data = [];
        foreach (Servers::all() as $server) {
            $ch = curl_init(rtrim($server->link, '/') . '/api/' . $server->token . '/online');
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPGET => true,
                CURLOPT_CONNECTTIMEOUT => 10,
                CURLOPT_TIMEOUT => 30,
                CURLOPT_FOLLOWLOCATION => false,
                CURLOPT_HTTPHEADER => ['Accept: application/json'],
            ]);
            $raw = curl_exec($ch);
            $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($code !== 200 || $raw === false) {
                continue;
            }

            $users = json_decode($raw, true);
            if (!is_array($users)) {
                continue;
            }
            foreach ($users as $remoteUser) {
                if (!empty($remoteUser['username'])) {
                    $data[] = $remoteUser;
                }
            }
        }
        return $data;
    }

    private function memory(): array
    {
        $values = [];
        foreach (file('/proc/meminfo', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
            if (preg_match('/^(MemTotal|MemAvailable):\s+(\d+)\s+kB$/', $line, $m)) {
                $values[$m[1]] = (int) $m[2] * 1024;
            }
        }
        $total = max(1, $values['MemTotal'] ?? 1);
        $available = $values['MemAvailable'] ?? 0;
        $used = max(0, $total - $available);
        return [$total, $used, round(($used / $total) * 100)];
    }

    private function traffic(): array
    {
        $rx = 0;
        $tx = 0;
        foreach (glob('/sys/class/net/*/statistics/rx_bytes') ?: [] as $file) {
            $rx += (int) @file_get_contents($file);
        }
        foreach (glob('/sys/class/net/*/statistics/tx_bytes') ?: [] as $file) {
            $tx += (int) @file_get_contents($file);
        }
        return [$rx, $tx];
    }

    private function formatBytes(float $bytes): string
    {
        if ($bytes <= 0) {
            return '0 B';
        }
        $sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
        $i = min((int) floor(log($bytes, 1024)), count($sizes) - 1);
        return round($bytes / (1024 ** $i), 1) . ' ' . $sizes[$i];
    }

    public function index()
    {
        $this->check();

        $onlineUser = count($this->onlineUsers());
        [$memTotal, $memUsed, $ramUsage] = $this->memory();
        $load = sys_getloadavg()[0] ?? 0;
        $cpuCount = max(1, substr_count((string) @file_get_contents('/proc/cpuinfo'), "processor\t:"));
        $cpuUsage = min(100, round(($load / $cpuCount) * 100));

        $diskTotal = max(1, (int) @disk_total_space(base_path()));
        $diskFree = max(0, (int) @disk_free_space(base_path()));
        $diskUsage = round((($diskTotal - $diskFree) / $diskTotal) * 100);
        [$download, $upload] = $this->traffic();

        $all_user = Users::count();
        $active_user = Users::where('status', 'active')->count();
        $deactive_user = Users::where('status', 'deactive')->count();
        $trafficTotal = Traffic::sum('total');
        $traffic_total = $this->formatBytes(((float) $trafficTotal) * 1024 * 1024);

        return view('dashboard.home', [
            'alluser' => $all_user,
            'active_user' => $active_user,
            'deactive_user' => $deactive_user,
            'online_user' => $onlineUser,
            'cpu_free' => $cpuUsage,
            'ram_free' => $ramUsage,
            'disk_free' => $diskUsage,
            'traffic_total' => $traffic_total,
            'traffic_download' => $this->formatBytes($download),
            'traffic_upload' => $this->formatBytes($upload),
        ]);
    }
}
