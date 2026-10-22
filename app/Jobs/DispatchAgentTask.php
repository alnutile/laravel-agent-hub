<?php

namespace App\Jobs;

use App\Models\AgentTask;
use App\Services\Grokked;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Throwable;

class DispatchAgentTask implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public int $timeout = 30;

    public function __construct(public int $taskId) {}

    public function handle(Grokked $grokked): void
    {
        if (! AgentTask::whereKey($this->taskId)->where('status', 'queued')->update(['status' => 'dispatching'])) {
            return;
        }
        $task = AgentTask::findOrFail($this->taskId);
        if ($task->driver === 'demo') {
            $task->update(['status' => 'succeeded', 'result' => 'DEMO ONLY: task recorded and processed. No external action was performed.']);

            return;
        }
        try {
            if ($task->driver !== 'grokked') {
                throw new \RuntimeException('Unsupported driver');
            }
            $id = $grokked->start($task);
            $task->update(['remote_id' => $id, 'status' => 'running']);
        } catch (Throwable $e) {
            $task->update(['status' => 'dispatch_unknown', 'result' => 'Submission could not be confirmed. Inspect Grokked before submitting again.']);
            Log::warning('Agent dispatch needs reconciliation', ['task_id' => $task->id, 'error_type' => $e::class]);
        }
    }
}
