<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RouteUsername
{
    public function handle(Request $request, Closure $next): Response
    {
        $username = $request->route('username');

        if (is_string($username) && $username !== '') {
            $request->merge(['username' => $username]);
        }

        return $next($request);
    }
}
