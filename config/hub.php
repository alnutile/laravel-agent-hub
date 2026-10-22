<?php

return [
    'driver' => env('AGENT_DRIVER', 'demo'),
    'grokked_url' => env('GROKKED_URL'),
    'grokked_token' => env('GROKKED_TOKEN'),
    'bot_id' => env('GROKKED_BOT_ID'),
    'allowed_domains' => array_values(array_filter(array_map('trim', explode(',', env('AGENT_ALLOWED_DOMAINS', 'example.com'))))),
    'max_usd' => (float) env('AGENT_MAX_USD', 2),
    'max_steps' => (int) env('AGENT_MAX_STEPS', 30),
];
