<?php

namespace App\Http\Controllers;

use App\Models\Admins;
use App\Models\Packages;
use App\Models\Servers;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class PackagesController extends Controller
{
    public function __construct()
    {
        $this->middleware('auth:admins');
    }

    private function check(): void
    {
        abort_unless(Auth::guard('admins')->user()?->permission === 'admin', 403);
    }

    public function index()
    {
        $this->check();
        $packages = Packages::orderByDesc('id')->get();
        $servers = Servers::orderBy('id')->get();
        return view('dashboard.package', compact('packages', 'servers'));
    }

    public function insert(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'amount' => ['required', 'numeric', 'min:0'],
            'day' => ['required', 'integer', 'min:1'],
            'multi' => ['required', 'string', 'max:50'],
            'serverid' => ['required', 'integer', 'exists:servers,id'],
            'multiuser' => ['required', 'integer', 'min:1'],
            'traffic' => ['required', 'numeric', 'min:0'],
        ]);

        Packages::create([
            'title' => $data['title'],
            'amount' => $data['amount'],
            'day' => $data['day'],
            'multi' => $data['multi'],
            'server' => $data['serverid'],
            'traffic' => $data['traffic'],
            'multiuser' => $data['multiuser'],
        ]);

        return redirect()->route('package');
    }

    public function edit(Request $request, $id)
    {
        $this->check();
        abort_unless(is_numeric($id), 400, 'Not Valid ID');
        $package = Packages::whereKey((int) $id)->get();
        abort_if($package->isEmpty(), 404);
        $servers = Servers::orderBy('id')->get();
        return view('dashboard.edit.package', compact('package', 'servers'));
    }

    public function update(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'id' => ['required', 'integer', 'exists:packages,id'],
            'title' => ['required', 'string', 'max:255'],
            'amount' => ['required', 'numeric', 'min:0'],
            'day' => ['required', 'integer', 'min:1'],
            'multi' => ['required', 'string', 'max:50'],
            'serverid' => ['required', 'integer', 'exists:servers,id'],
            'multiuser' => ['required', 'integer', 'min:1'],
            'traffic' => ['required', 'numeric', 'min:0'],
        ]);

        Packages::whereKey($data['id'])->update([
            'title' => $data['title'],
            'amount' => $data['amount'],
            'day' => $data['day'],
            'multi' => $data['multi'],
            'server' => $data['serverid'],
            'traffic' => $data['traffic'],
            'multiuser' => $data['multiuser'],
        ]);

        return redirect()->route('package');
    }

    public function delete(Request $request, $id)
    {
        $this->check();
        abort_unless(is_numeric($id), 400, 'Not Valid ID');
        Packages::whereKey((int) $id)->delete();
        return redirect()->route('package');
    }
}
