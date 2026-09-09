<?php

namespace App\Http\Controllers;

use App\Models\Users;
use App\Models\Servers;
use App\Models\Packages;
use Illuminate\Http\Request;

class DetailController extends Controller
{
    private function resolveKey(string $encoded): array
    {
        $decoded = base64_decode($encoded, true);
        abort_unless($decoded !== false, 404);

        $parts = explode('#', $decoded, 3);
        abort_unless(count($parts) === 3 && ctype_digit($parts[0]) && $parts[1] !== '' && $parts[2] !== '', 404);

        return [$parts[0], $parts[1], $parts[2]];
    }

    public function index(Request $request, $key)
    {
        abort_unless(is_string($key), 400, 'Not Valid Key');
        [$id, $username, $created] = $this->resolveKey($key);

        $user = Users::whereKey((int) $id)
            ->where('username', $username)
            ->where('created_at', $created)
            ->first();
        abort_if(!$user, 403);

        $servers = Servers::orderBy('id')->get();
        return view('detail', ['user' => collect([$user]), 'servers' => $servers, 'key_org' => $key]);
    }

    public function update(Request $request, $key)
    {
        abort_unless(is_string($key), 400, 'Not Valid Key');
        [$id, $username, $created] = $this->resolveKey($key);

        $data = $request->validate([
            'serverid' => ['required', 'integer', 'exists:servers,id'],
        ]);

        $user = Users::whereKey((int) $id)
            ->where('username', $username)
            ->where('created_at', $created)
            ->first();
        abort_if(!$user, 403);

        $oldServer = Servers::find($user->server);
        $newServer = Servers::find($data['serverid']);
        $package = Packages::find($user->package);
        abort_if(!$oldServer || !$newServer || !$package, 404);

        $delete = $this->serverRequest($oldServer, '/api/delete', ['username' => $username]);
        if (!in_array($delete['message'] ?? null, ['User Deleted', 'Not Exist User'], true)) {
            return back()->with('error', 'Unable to remove the user from the current server.');
        }

        $createdRemote = $this->serverRequest($newServer, '/api/adduser', [
            'username' => $username,
            'password' => $user->password,
            'email' => $user->email,
            'mobile' => $user->mobile,
            'multiuser' => $package->multiuser,
            'traffic' => $user->traffic,
            'type_traffic' => 'mb',
            'expdate' => $user->end_date,
            'desc' => $user->desc,
        ]);

        if (($createdRemote['message'] ?? null) === 'User Created') {
            $user->update(['server' => $newServer->id]);
            return back()->with('success', 'Change Server Success');
        }

        return back()->with('error', 'Unable to create the user on the new server.');
    }

    private function serverRequest(Servers $server, string $path, array $post): array
    {
        $ch = curl_init(rtrim($server->link, '/') . $path);
        $post['token'] = $server->token;
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $post,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_TIMEOUT => 30,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_HTTPHEADER => ['Accept: application/json'],
        ]);
        $raw = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($raw === false || $code < 200 || $code >= 300) {
            return [];
        }
        $decoded = json_decode($raw, true);
        return is_array($decoded) ? $decoded : [];
    }
}
