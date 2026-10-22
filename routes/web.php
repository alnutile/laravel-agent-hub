<?php

use App\Jobs\DispatchAgentTask;
use App\Models\AgentTask;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/login', fn () => view('login'))->name('login');
Route::post('/login', function (Request $request) {
    $credentials = $request->validate(['email' => 'required|email', 'password' => 'required|string']);
    if (! Auth::attempt($credentials)) {
        return back()->withErrors(['email' => 'Invalid credentials.']);
    }
    $request->session()->regenerate();

    return redirect('/');
})->middleware('throttle:5,1');
Route::middleware('auth')->group(function () {
    Route::get('/', fn () => view('hub', ['tasks' => AgentTask::where('user_id', Auth::id())->latest()->limit(30)->get()]));
    Route::post('/tasks', function (Request $request) {
        $input = $request->validate(['goal' => 'required|string|min:5|max:10000', 'request_key' => 'required|uuid']);
        DB::transaction(function () use ($input) {
            $task = AgentTask::firstOrCreate(['user_id' => Auth::id(), 'request_key' => $input['request_key']], [
                'goal' => $input['goal'], 'driver' => config('hub.driver'), 'status' => 'queued',
                'context' => ['bot_id' => config('hub.bot_id'), 'allowed_domains' => config('hub.allowed_domains'),
                    'max_usd' => config('hub.max_usd'), 'max_steps' => config('hub.max_steps')],
            ]);
            if ($task->wasRecentlyCreated) {
                DispatchAgentTask::dispatch($task->id);
            }
        });

        return redirect('/');
    })->middleware('throttle:10,1');
    Route::post('/logout', function (Request $request) {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect('/login');
    });
});
