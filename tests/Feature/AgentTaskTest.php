<?php

namespace Tests\Feature;

use App\Jobs\DispatchAgentTask;
use App\Models\AgentTask;
use App\Models\User;
use App\Services\Grokked;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Str;
use Tests\TestCase;

class AgentTaskTest extends TestCase
{
    use RefreshDatabase;

    public function test_demo_task_completes_without_network_access(): void
    {
        Http::preventStrayRequests();
        config(['hub.driver' => 'demo']);
        $this->actingAs(User::factory()->create())->post('/tasks', [
            'goal' => 'Inspect example.com', 'request_key' => (string) Str::uuid(),
        ])->assertRedirect('/');
        $this->assertDatabaseHas('agent_tasks', ['status' => 'succeeded', 'driver' => 'demo']);
        $this->assertStringContainsString('DEMO ONLY', AgentTask::first()->result);
        Http::assertNothingSent();
    }

    public function test_remote_completion_is_synchronized(): void
    {
        config(['hub.grokked_url' => 'https://agent.test', 'hub.grokked_token' => 'test-only']);
        Http::fake(['*' => Http::response(['run' => ['state' => 'succeeded', 'outcome_summary' => 'Inspection complete']])]);
        $task = AgentTask::create(['user_id' => User::factory()->create()->id, 'request_key' => Str::uuid(), 'goal' => 'Inspect example.com', 'driver' => 'grokked', 'context' => [], 'status' => 'running', 'remote_id' => 'run-1']);
        $this->artisan('hub:sync')->assertSuccessful();
        $this->assertSame('succeeded', $task->fresh()->status);
        $this->assertSame('Inspection complete', $task->fresh()->result);
    }

    public function test_authentication_and_owner_isolation(): void
    {
        $this->get('/')->assertRedirect('/login');
        $owner = User::factory()->create();
        AgentTask::create(['user_id' => $owner->id, 'request_key' => Str::uuid(), 'goal' => 'Private task alpha', 'driver' => 'demo', 'context' => []]);
        $this->actingAs(User::factory()->create())->get('/')->assertOk()->assertDontSee('Private task alpha');
        $this->actingAs($owner)->get('/')->assertSee('Private task alpha');
    }

    public function test_repeated_submission_dispatches_only_once(): void
    {
        Queue::fake();
        $this->actingAs(User::factory()->create());
        $payload = ['goal' => 'Inspect example.com', 'request_key' => (string) Str::uuid()];
        $this->post('/tasks', $payload)->assertRedirect('/');
        $this->post('/tasks', $payload)->assertRedirect('/');
        $this->assertDatabaseCount('agent_tasks', 1);
        Queue::assertPushed(DispatchAgentTask::class, 1);
    }

    public function test_uncertain_dispatch_is_not_retried(): void
    {
        config(['hub.grokked_url' => 'https://agent.test', 'hub.grokked_token' => 'test-only']);
        Http::fake(['*' => Http::failedConnection()]);
        $task = AgentTask::create(['user_id' => User::factory()->create()->id, 'request_key' => Str::uuid(), 'goal' => 'Inspect example.com', 'driver' => 'grokked', 'context' => []]);
        $job = new DispatchAgentTask($task->id);
        $job->handle(new Grokked);
        $this->assertSame('dispatch_unknown', $task->fresh()->status);
        Http::fake(['*' => Http::response(['run' => ['id' => 'duplicate']])]);
        $job->handle(new Grokked);
        Http::assertNothingSent();
    }

    public function test_dispatch_freezes_limits_and_tracks_remote_run(): void
    {
        config(['hub.grokked_url' => 'https://agent.test', 'hub.grokked_token' => 'test-only']);
        Http::fake(['*' => Http::response(['run' => ['id' => 'run-1']])]);
        $task = AgentTask::create(['user_id' => User::factory()->create()->id, 'request_key' => Str::uuid(), 'goal' => 'Inspect example.com', 'driver' => 'grokked', 'context' => ['bot_id' => 'bot-1', 'max_usd' => 2, 'max_steps' => 10, 'allowed_domains' => ['example.com']]]);
        (new DispatchAgentTask($task->id))->handle(new Grokked);
        Http::assertSent(fn ($request) => $request['max_steps'] === 10 && $request['new_thread'] === true);
        $this->assertSame('run-1', $task->fresh()->remote_id);
        $this->assertSame('running', $task->fresh()->status);
    }
}
