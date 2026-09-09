<?php

namespace App\Http\Controllers;

use App\Models\Admins;
use App\Models\TransRess;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;

class AdminsController extends Controller
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
        $admins = Admins::where('permission', 'reseller')->orderByDesc('id')->get();
        return view('admins.index', compact('admins'));
    }

    public function insert(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'username' => ['required', 'string', 'max:64', 'regex:/^[A-Za-z0-9._-]+$/', 'unique:admins,username'],
            'password' => ['required', 'string', 'min:8', 'max:255'],
            'credit' => ['required', 'numeric', 'min:0'],
        ]);

        Admins::create([
            'username' => $data['username'],
            'password' => Hash::make($data['password']),
            'permission' => 'reseller',
            'credit' => $data['credit'],
            'status' => 'active',
        ]);

        return redirect()->route('admins');
    }

    public function activeadmin(Request $request, $username)
    {
        $this->check();
        abort_unless(is_string($username), 400, 'Not Valid Username');
        Admins::where('username', $username)->where('permission', 'reseller')->update(['status' => 'active']);
        return back()->with('success', 'Activated');
    }

    public function deactiveadmin(Request $request, $username)
    {
        $this->check();
        abort_unless(is_string($username), 400, 'Not Valid Username');
        Admins::where('username', $username)->where('permission', 'reseller')->update(['status' => 'deactive']);
        return back()->with('success', 'Deactivated');
    }

    public function deleteadmin(Request $request, $username)
    {
        $this->check();
        abort_unless(is_string($username), 400, 'Not Valid Username');
        Admins::where('username', $username)->where('permission', 'reseller')->delete();
        return back()->with('success', 'Deleted');
    }

    public function edit(Request $request, $username)
    {
        $this->check();
        abort_unless(is_string($username), 400, 'Not Valid Username');
        $user = Admins::where('username', $username)->where('permission', 'reseller')->firstOrFail();
        return view('admins.edit')->with('show', $user);
    }

    public function update(Request $request)
    {
        $this->check();
        $data = $request->validate([
            'username' => ['required', 'string', 'max:64'],
            'password' => ['nullable', 'string', 'min:8', 'max:255'],
            'credit' => ['required', 'numeric', 'min:0'],
        ]);

        $admin = Admins::where('username', $data['username'])->where('permission', 'reseller')->firstOrFail();
        $oldCredit = (float) $admin->credit;
        $newCredit = (float) $data['credit'];

        if ($newCredit !== $oldCredit) {
            TransRess::create([
                'desc_trans' => $newCredit > $oldCredit ? 'Increase credit (Admin)' : 'Credit withdrawal (Admin)',
                'amount_trans' => abs($newCredit - $oldCredit),
                'date_time' => time(),
                'username_trans' => $admin->username,
            ]);
        }

        $admin->credit = $newCredit;
        if (!empty($data['password'])) {
            $admin->password = Hash::make($data['password']);
        }
        $admin->save();

        return back()->with('success', 'Update Success');
    }
}
