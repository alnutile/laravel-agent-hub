"""Exercise a disposable image through HTTP and its real database queue."""
import base64
import html
import http.cookiejar
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid


def docker(*args, **kwargs):
    return subprocess.check_output(["docker", *args], text=True, **kwargs).strip()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


image = sys.argv[1] if len(sys.argv) > 1 else "agent-hub:test"
name = "hub-smoke-" + uuid.uuid4().hex[:12]
# Ephemeral test-only identity; never an operator on a deployed hub.
password = uuid.uuid4().hex
key = base64.b64encode(os.urandom(32)).decode()
try:
    docker("run", "-d", "--name", name, "-p", "127.0.0.1::80",
           "-e", "APP_KEY=base64:" + key, "-e", "APP_ENV=production",
           "-e", "APP_DEBUG=false", "-e", "LOG_CHANNEL=stderr",
           "-e", "DB_CONNECTION=sqlite", "-e", "DB_DATABASE=/var/www/html/storage/app/hub.sqlite",
           "-e", "CACHE_STORE=database", "-e", "SESSION_DRIVER=database",
           "-e", "SESSION_SECURE_COOKIE=false", "-e", "QUEUE_CONNECTION=database",
           "-e", "AGENT_DRIVER=demo", image)
    docker("exec", name, "sh", "-c",
           "touch storage/app/hub.sqlite && chown www-data:www-data storage/app/hub.sqlite")
    docker("exec", "--user", "www-data", name, "php", "artisan", "migrate", "--force")
    docker("exec", "-i", "--user", "www-data", name, "php", input='''<?php
require 'vendor/autoload.php';
$app = require 'bootstrap/app.php';
$app->make(Illuminate\\Contracts\\Console\\Kernel::class)->bootstrap();
App\\Models\\User::create(['name' => 'Smoke test', 'email' => 'smoke@example.test',
    'password' => Illuminate\\Support\\Facades\\Hash::make('%s')]);
''' % password)
    port = docker("port", name, "80/tcp").rsplit(":", 1)[1]
    base = "http://127.0.0.1:" + port
    client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def request(path, data=None):
        body = urllib.parse.urlencode(data).encode() if data is not None else None
        with client.open(base + path, data=body, timeout=10) as response:
            return response.geturl(), response.read().decode()

    def token(page):
        match = re.search(r'name="_token" value="([^"]+)"', page)
        require(match, "CSRF token missing")
        return html.unescape(match.group(1))

    for attempt in range(30):
        try:
            _, page = request("/login")
            break
        except (urllib.error.URLError, OSError):
            if attempt == 29:
                raise
            time.sleep(2)
    require(request("/")[0].endswith("/login"), "Anonymous hub access must require login")
    url, page = request("/login", {"_token": token(page), "email": "smoke@example.test", "password": password})
    require(urllib.parse.urlparse(url).path == "/" and "New task" in page, "Operator login failed")
    payload = {"_token": token(page), "request_key": str(uuid.uuid4()), "goal": "Inspect the synthetic demo site"}
    _, page = request("/tasks", payload)
    require("queued" in page and payload["goal"] in page, "Task was not queued")
    request("/tasks", payload)  # The same request must not enqueue a duplicate.
    docker("exec", "--user", "www-data", name, "php", "artisan", "queue:work", "--stop-when-empty", "--tries=1", "--timeout=30")
    _, page = request("/")
    require("succeeded" in page and "DEMO ONLY" in page, "Database worker did not complete the demo")
    require(page.count(payload["goal"]) == 1, "Duplicate task created")
    require(request("/up")[1], "Health endpoint failed")
    url, _ = request("/logout", {"_token": token(page)})
    require(url.endswith("/login") and request("/")[0].endswith("/login"), "Logout failed")
    print("Container smoke test passed: migrations, login, task deduplication, database queue, demo completion, health and logout.")
except Exception:
    subprocess.run(["docker", "logs", "--tail", "80", name], check=False)
    raise
finally:
    subprocess.run(["docker", "rm", "-fv", name], check=False, stdout=subprocess.DEVNULL)
