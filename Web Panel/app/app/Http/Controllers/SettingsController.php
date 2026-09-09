<?php

namespace App\Http\Controllers;

use App\Models\Users;
use App\Models\Admins;
use App\Models\Api;
use App\Models\Settings;
use App\Models\Traffic;
use App\Models\Servers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class SettingsController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth:admins');
    }

    private function check(): void
    {
        abort_unless(Auth::guard('admins')->user()?->permission === 'admin', 403);
    }

    public function defualt()
    {
        $this->check();
        return redirect()->route('settings', ['name' => 'server']);
    }

    public function index(Request $request, $name)
    {
        $this->check();
        abort_unless(is_string($name) && in_array($name, ['server', 'backup', 'api', 'block', 'fakeaddress', 'wordpress'], true), 404);

        if ($name === 'server') {
            $servers = Servers::orderBy('id')->get();
            return view('settings.index', compact('servers'));
        }

        if ($name === 'backup') {
            $lists = collect(Storage::files('backup'))
                ->map(fn ($path) => basename($path))
                ->sort()
                ->values()
                ->all();
            return view('settings.backup', compact('lists'));
        }

        if ($name === 'api') {
            $apis = Api::orderByDesc('id')->get();
            return view('settings.api', compact('apis'));
        }

        if ($name === 'block') {
            $status = (int) Process::run(['iptables', '-L', 'OUTPUT'])->successful();
            return view('settings.block', compact('status'));
        }

        if ($name === 'fakeaddress') {
            return view('settings.fake');
        }

        $host = request()->getHost();
        $protocol = request()->secure() ? 'https' : 'http';
        $address = $protocol . '://' . $host;
        return view('settings.wordpress', compact('address'));
    }

    public function add_server(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'link' => ['required', 'url', 'max:2048'],
            'token' => ['required', 'string', 'max:255'],
            'name' => ['required', 'string', 'max:255'],
            'port' => ['required', 'integer', 'between:1,65535'],
            'port_tls' => ['required', 'integer', 'between:1,65535'],
        ]);
        Servers::create([
            'link' => rtrim($data['link'], '/'),
            'token' => $data['token'],
            'name' => $data['name'],
            'port_connection' => $data['port'],
            'port_connection_tls' => $data['port_tls'],
        ]);
        return redirect()->route('settings', ['name' => 'server']);
    }

    public function edit_server(Request $request, $id)
    {
        $this->check();
        abort_unless(is_numeric($id), 400, 'Not Valid ID');
        $server = Servers::whereKey((int) $id)->get();
        abort_if($server->isEmpty(), 404);
        return view('settings.edit.server', compact('server'));
    }

    public function update_server(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'id' => ['required', 'integer', 'exists:servers,id'],
            'link' => ['required', 'url', 'max:2048'],
            'token' => ['required', 'string', 'max:255'],
            'name' => ['required', 'string', 'max:255'],
            'port' => ['required', 'integer', 'between:1,65535'],
            'port_tls' => ['required', 'integer', 'between:1,65535'],
        ]);
        Servers::whereKey($data['id'])->update([
            'link' => rtrim($data['link'], '/'),
            'token' => $data['token'],
            'name' => $data['name'],
            'port_connection' => $data['port'],
            'port_connection_tls' => $data['port_tls'],
        ]);
        return redirect()->route('settings', ['name' => 'server']);
    }

    public function delete_server(Request $request, $id)
    {
        $this->check();
        abort_unless(is_numeric($id), 400, 'Not Valid ID');
        Servers::whereKey((int) $id)->delete();
        return redirect()->route('settings', ['name' => 'server']);
    }

    public function update_telegram(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'tokenbot' => ['required', 'string', 'max:255'],
            'idtelegram' => ['required', 'string', 'max:255'],
        ]);
        Settings::updateOrCreate(['id' => 1], [
            't_token' => $data['tokenbot'],
            't_id' => $data['idtelegram'],
        ]);
        return redirect()->route('settings', ['name' => 'telegram']);
    }

    public function upload_backup(Request $request)
    {
        $this->check();
        $request->validate([
            'file' => ['required', 'file', 'mimetypes:text/plain,application/sql', 'max:51200'],
        ]);

        $request->file('file')->storeAs('backup', Str::uuid() . '.sql');
        return redirect()->route('settings', ['name' => 'backup']);
    }

    private function backupPath(string $name): string
    {
        abort_unless($name === basename($name) && preg_match('/^[A-Za-z0-9._-]+$/', $name), 400, 'Invalid backup name');
        $path = storage_path('app/backup/' . $name);
        abort_unless(is_file($path), 404);
        return $path;
    }

    public function delete_backup(Request $request, $name)
    {
        $this->check();
        $path = $this->backupPath((string) $name);
        unlink($path);
        return redirect()->route('settings', ['name' => 'backup']);
    }

    public function restore_backup(Request $request, $name)
    {
        $this->check();
        $path = $this->backupPath((string) $name);
        $sql = file_get_contents($path);
        abort_if($sql === false, 500, 'Unable to read backup');

        $result = Process::input($sql)
            ->env(['MYSQL_PWD' => (string) env('DB_PASSWORD')])
            ->timeout(120)
            ->run(['mysql', '-u', (string) env('DB_USERNAME'), (string) env('DB_DATABASE', 'Xcs')]);

        abort_unless($result->successful(), 500, 'Database restore failed');

        foreach (Users::all() as $user) {
            if (!Traffic::where('username', $user->username)->exists()) {
                Traffic::create([
                    'username' => $user->username,
                    'download' => 0,
                    'upload' => 0,
                    'total' => 0,
                ]);
            }
        }

        return redirect()->route('settings', ['name' => 'backup']);
    }

    public function make_backup()
    {
        $this->check();
        $date = now()->format('Y-m-d---H-i-s');
        $result = Process::env(['MYSQL_PWD' => (string) env('DB_PASSWORD')])
            ->timeout(120)
            ->run(['mysqldump', '-u', (string) env('DB_USERNAME'), (string) env('DB_DATABASE', 'Xcs')]);
        abort_unless($result->successful(), 500, 'Database backup failed');

        Storage::put('backup/Xcs-' . $date . '.sql', $result->output());
        return redirect()->route('settings', ['name' => 'backup']);
    }

    public function download_backup(Request $request, $name)
    {
        $this->check();
        $path = $this->backupPath((string) $name);
        return response()->download($path, basename($path), ['Content-Type' => 'application/sql']);
    }

    public function insert_api(Request $request)
    {
        $this->check();
        $user = Auth::guard('admins')->user();
        $data = $request->validate([
            'desc' => ['required', 'string', 'max:255'],
            'allowip' => ['required', 'string', 'max:255'],
        ]);
        Api::create([
            'username' => $user->username,
            'token' => time() . Str::upper(Str::random(30)),
            'description' => $data['desc'],
            'allow_ip' => $data['allowip'],
            'status' => 'active',
        ]);
        return redirect()->route('settings', ['name' => 'api']);
    }

    public function renew_api(Request $request, $id)
    {
        $this->check();
        abort_unless(is_numeric($id), 400, 'Not Valid ID');
        Api::whereKey((int) $id)->update(['token' => time() . Str::upper(Str::random(30))]);
        return redirect()->route('settings', ['name' => 'api']);
    }

    public function delete_api(Request $request, $id)
    {
        $this->check();
        abort_unless(is_numeric($id), 400, 'Not Valid ID');
        Api::whereKey((int) $id)->delete();
        return redirect()->route('settings', ['name' => 'api']);
    }

    public function block(Request $request)
    {
        $this->check();
        $data = $request->validate(['status' => ['required', 'in:active,inactive']]);
        $rules = [
            ['-A', 'OUTPUT', '-m', 'geoip', '-p', 'tcp', '--destination-port', '80', '--dst-cc', 'IR', '-j', 'DROP'],
            ['-A', 'OUTPUT', '-m', 'geoip', '-p', 'tcp', '--destination-port', '443', '--dst-cc', 'IR', '-j', 'DROP'],
        ];

        foreach ($rules as $rule) {
            Process::run(array_merge(['iptables'], $data['status'] === 'active' ? $rule : array_replace($rule, [0 => '-D'])));
        }
        return redirect()->route('settings', ['name' => 'block']);
    }

    public function fakeurl(Request $request)
    {
        $this->check();
        $data = $request->validate(['fake_address' => ['required', 'url', 'max:2048']]);
        $host = parse_url($data['fake_address'], PHP_URL_HOST);
        abort_unless($host !== null, 422, 'Invalid URL');

        $txt = "<?php\n\n$url = " . var_export($data['fake_address'], true) . ";\n$ch = curl_init($url);\ncurl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_FOLLOWLOCATION => false, CURLOPT_CONNECTTIMEOUT => 10, CURLOPT_TIMEOUT => 20, CURLOPT_SSL_VERIFYPEER => true, CURLOPT_SSL_VERIFYHOST => 2]);\n$data = curl_exec($ch);\n$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);\ncurl_close($ch);\nhttp_response_code($status >= 200 && $status < 600 ? $status : 502);\necho $data === false ? 'Upstream unavailable' : $data;\n";
        file_put_contents('/var/www/html/example/index.php', $txt, LOCK_EX);
        return redirect()->route('settings', ['name' => 'fakeaddress']);
    }
}
