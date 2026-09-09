<?php

namespace App\Http\Controllers;

use App\Models\Servers;
use App\Models\Traffic;
use App\Models\Users;

class FixerController extends Controller
{
    public function cronexp()
    {
        $users = Users::where('status', 'active')->get();
        foreach ($users as $user) {
            if (empty($user->end_date)) {
                continue;
            }

            if (strtotime($user->end_date) > strtotime(now()->toDateString())) {
                continue;
            }

            $server = Servers::find($user->server);
            if (!$server) {
                continue;
            }

            $response = $this->serverRequest($server, '/api/delete', ['username' => $user->username]);
            if (in_array($response['message'] ?? null, ['User Deleted', 'Not Exist User'], true)) {
                $user->update(['status' => 'expired']);
            }
        }

        $users = Users::where('status', 'active')->where('traffic', '>', 0)->get();
        foreach ($users as $user) {
            $traffic = Traffic::where('username', $user->username)->first();
            if (!$traffic || $traffic->total === null || $user->traffic >= $traffic->total) {
                continue;
            }

            $server = Servers::find($user->server);
            if (!$server) {
                continue;
            }

            $response = $this->serverRequest($server, '/api/delete', ['username' => $user->username]);
            if (in_array($response['message'] ?? null, ['User Deleted', 'Not Exist User'], true)) {
                $user->update(['status' => 'traffic']);
            }
        }

        $this->synstraffics();
        return response()->json(['status' => 'ok']);
    }

    public function synstraffics()
    {
        $users = Users::where('status', 'active')->get();
        foreach ($users->groupBy('server') as $serverId => $serverUsers) {
            $server = Servers::find($serverId);
            if (!$server) {
                continue;
            }

            $response = $this->serverRequest($server, '/api/' . $server->token . '/online', [], 'GET');
            $onlineUsers = is_array($response) ? $response : [];
            foreach ($onlineUsers as $onlineUser) {
                $username = $onlineUser['username'] ?? null;
                $total = $onlineUser['traffics']['total'] ?? null;
                if ($username === null || $total === null || !$serverUsers->contains('username', $username)) {
                    continue;
                }

                Traffic::where('username', $username)->update([
                    'download' => $onlineUser['traffics']['download'] ?? 0,
                    'upload' => $onlineUser['traffics']['upload'] ?? 0,
                    'total' => $total,
                ]);
            }
        }
    }

    private function serverRequest(Servers $server, string $path, array $post = [], string $method = 'POST'): array
    {
        $url = rtrim($server->link, '/') . $path;
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => ['Accept: application/json'],
        ]);

        if ($method !== 'GET') {
            $post['token'] = $server->token;
            curl_setopt($ch, CURLOPT_POSTFIELDS, $post);
        }

        $raw = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($raw === false || $httpCode < 200 || $httpCode >= 300) {
            return [];
        }

        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }
}
