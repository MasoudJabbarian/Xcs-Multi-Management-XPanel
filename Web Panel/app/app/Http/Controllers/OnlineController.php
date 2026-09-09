<?php

namespace App\Http\Controllers;

use App\Models\Servers;
use App\Models\Users;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Process;

class OnlineController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth:admins');
    }

    private function check(): void
    {
        abort_unless(Auth::guard('admins')->user()?->permission === 'admin', 403);
    }

    public function kill_pid(Request $request, $pid)
    {
        $this->check();
        abort_unless(ctype_digit((string) $pid) && (int) $pid > 0, 400, 'Not Valid PID');
        Process::run(['kill', '-9', (string) (int) $pid]);
        return back()->with('success', 'Killed');
    }

    public function kill_user(Request $request, $username)
    {
        $this->check();
        abort_unless(is_string($username) && preg_match('/^[A-Za-z0-9._-]+$/', $username), 400, 'Not Valid Username');
        Process::run(['killall', '-u', $username]);
        return back()->with('success', 'Killed');
    }

    public function index()
    {
        $data = [];
        $currentUser = Auth::guard('admins')->user();

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
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            if ($httpCode !== 200 || $raw === false) {
                continue;
            }

            $onlineUsers = json_decode($raw, true);
            if (!is_array($onlineUsers)) {
                continue;
            }

            foreach ($onlineUsers as $online) {
                $username = $online['username'] ?? null;
                if (!$username) {
                    continue;
                }

                if ($currentUser->permission === 'reseller' && !Users::where('customer_user', $currentUser->username)->where('username', $username)->exists()) {
                    continue;
                }

                $data[] = [
                    'server' => $server->name,
                    'username' => $username,
                    'color' => (($online['connection'] ?? '') === 'one connection') ? '#269393' : '#dc2626',
                    'ip' => $online['ip'] ?? '',
                    'pid' => $online['pid'] ?? '',
                ];
            }
        }

        return view('users.online', ['data' => json_decode(json_encode($data))]);
    }

    public function filtering()
    {
        $data = [];
        $serverip = request()->server('SERVER_ADDR');
        $sshPort = env('PORT_SSH');
        if (!$serverip || !is_numeric($sshPort)) {
            return view('dashboard.filtering', compact('data'));
        }

        $ch = curl_init();
        curl_setopt_array($ch, [
            CURLOPT_URL => 'https://check-host.net/check-tcp?host=' . rawurlencode($serverip . ':' . (int) $sshPort) . '&max_nodes=50',
            CURLOPT_POST => true,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => ['Accept: application/json', 'Cache-Control: no-cache'],
        ]);
        $response = curl_exec($ch);
        curl_close($ch);
        $array = json_decode((string) $response, true);
        if (!is_array($array) || empty($array['request_id'])) {
            return view('dashboard.filtering', compact('data'));
        }

        sleep(3);
        $ch = curl_init('https://check-host.net/check-result/' . rawurlencode($array['request_id']));
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => ['Accept: application/json', 'Cache-Control: no-cache'],
        ]);
        $serverOutput = curl_exec($ch);
        curl_close($ch);
        $results = json_decode((string) $serverOutput, true);

        if (is_array($results)) {
            foreach ($results as $key => $value) {
                $flag = preg_replace('/[0-9]+/', '', str_replace('.node.check-host.net', '', $key));
                if (!in_array($flag, ['ir', 'us', 'fr', 'de'], true)) {
                    continue;
                }
                $status = isset($value[0]['time']) && is_numeric($value[0]['time']) ? 'Online' : 'Filter';
                $data[] = ['flag' => $flag, 'status' => $status];
            }
        }

        return view('dashboard.filtering', ['data' => json_decode(json_encode($data))]);
    }
}
