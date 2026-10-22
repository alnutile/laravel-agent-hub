@extends('layout')
@section('content')
<p>Describe the work. Track the handoff. Keep the boundaries visible.</p>
<section><h2>New task</h2><p>Driver: <strong>{{ config('hub.driver') }}</strong>. Domains: {{ implode(', ', config('hub.allowed_domains')) }}. Budget: ${{ config('hub.max_usd') }} / {{ config('hub.max_steps') }} steps.</p>
@if(config('hub.driver') === 'demo')<p>Demo mode records and completes tasks locally. No agent or model is called.</p>@else<p>Pilot: one trusted operator and one preconfigured Grokked bot. Only submit work within that bot's authority.</p>@endif
<form method="post" action="/tasks">@csrf<input type="hidden" name="request_key" value="{{ (string) Str::uuid() }}"><label>What should the agent do?<textarea name="goal" rows="4" minlength="5" maxlength="10000" required placeholder="Inspect the example site and summarize its navigation."></textarea></label><button>Submit task</button></form></section>
<h2>Your recent tasks</h2><p>Refresh to see updates. Remote runs are synchronized once a minute when the scheduler is running.</p>
@forelse($tasks as $task)<article><small>#{{ $task->id }} · {{ $task->driver }} · {{ $task->created_at }}</small><h3>{{ $task->status }}</h3><pre>{{ $task->goal }}</pre>@if($task->result)<pre>{{ $task->result }}</pre>@endif @if($task->remote_id)<small>Remote run: {{ $task->remote_id }}</small>@endif</article>@empty<p>No tasks yet.</p>@endforelse
@endsection
