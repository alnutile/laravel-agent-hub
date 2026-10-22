<?php

use App\Models\AgentTask;
use App\Models\User;
use App\Services\Grokked;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schedule;

Artisan::command('hub:user {email}', function () {
    $password = $this->secret('Password (minimum 12 characters)');
    if (! filter_var($this->argument('email'), FILTER_VALIDATE_EMAIL) || strlen($password ?? '') < 12) {
        $this->error('Valid email and password of at least 12 characters required.');

        return 1;
    }
    User::updateOrCreate(['email' => $this->argument('email')], ['name' => $this->argument('email'), 'password' => Hash::make($password)]);
    $this->info('Operator saved.');
});
Artisan::command('hub:sync', function (Grokked $grokked) {
    AgentTask::where('driver', 'grokked')->whereNotNull('remote_id')
        ->whereNotIn('status', ['succeeded', 'failed', 'cancelled'])->each(function ($task) use ($grokked) {
            try {
                $run = $grokked->read($task->remote_id);
                $task->update(['status' => $run['state'] ?? $task->status,
                    'result' => $run['outcome_summary'] ?? $run['state_reason'] ?? null]);
            } catch (Throwable $e) {
                Log::warning('Agent sync failed', ['task_id' => $task->id, 'error_type' => $e::class]);
            }
        });
});
Schedule::command('hub:sync')->everyMinute()->withoutOverlapping();
