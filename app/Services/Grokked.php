<?php

namespace App\Services;

use App\Models\AgentTask;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class Grokked
{
    private function client()
    {
        if (! config('hub.grokked_url') || ! config('hub.grokked_token')) {
            throw new RuntimeException('Grokked connection is not configured.');
        }

        return Http::baseUrl(config('hub.grokked_url'))->withToken(config('hub.grokked_token'))
            ->acceptJson()->connectTimeout(5)->timeout(20);
    }

    public function start(AgentTask $task): string
    {
        // No retry: upstream does not promise idempotency for POST /v1/runs.
        $id = $this->client()->post('/v1/runs', [
            ...$task->context, 'goal' => $task->goal, 'new_thread' => true,
        ])->throw()->json('run.id');
        if (! is_string($id) || $id === '') {
            throw new RuntimeException('Missing run ID.');
        }

        return $id;
    }

    public function read(string $id): array
    {
        $run = $this->client()->get('/v1/runs/'.rawurlencode($id))->throw()->json('run');
        if (! is_array($run)) {
            throw new RuntimeException('Invalid run response.');
        }

        return $run;
    }
}
