# Laravel Agent Hub

A working first slice of an internal agent hub: sign in, describe a task, dispatch it to a bounded agent, and see its status. The purpose is to remove friction in existing workflows. A useful pilot might gather UI release evidence for legal review; measure time saved and reviewer effort before adding platform features.

This is an independent proof of concept, not a BetterHelp production system.

## What works

- Laravel 13 operator login, per-user task history, database queue and scheduler.
- Explicit demo driver: local tasks, no external actions or model calls.
- Grokked HTTP adapter: new conversation per task, frozen domain/step/cost limits, remote run tracking and polling. An uncertain submission is never automatically repeated.
- Docker image; GitHub Actions tests, image build, container smoke test, immutable ECR publishing and SSM deployment.
- Terraform for a private EC2 host, encrypted retained disk, ECR, CloudWatch, runtime secret container and targeted deployment role.

The adapter follows [grokked-bot](https://github.com/alnutile/grokked-bot) at `3ed6e4a55a80ae85b242a7b91b239a27ae0ed1ac`. Its HTTP contract is tested with fakes; live integration needs a reachable daemon and configured bot.

## Run locally

Requires PHP 8.4, Composer 2, SQLite support and standard Laravel extensions. No frontend compilation is needed.

```bash
composer install
cp .env.example .env
php artisan key:generate
touch database/database.sqlite
php artisan migrate
php artisan hub:user you@example.com
php artisan serve
```

In two additional terminals:

```bash
php artisan queue:work --tries=1 --timeout=30
php artisan schedule:work
```

Open http://localhost:8000. Sign in with the provisioned operator. Submit a task; the default demo driver clearly marks it as a simulation. The account command prompts for the password without echoing it. There is no public signup or seeded password.

```bash
php artisan test
vendor/bin/pint --test
composer audit
```

## Connect Grokked

Set `AGENT_DRIVER=grokked`, `GROKKED_URL`, `GROKKED_TOKEN`, and `GROKKED_BOT_ID` in the local environment or runtime secret. Configure `AGENT_ALLOWED_DOMAINS`, `AGENT_MAX_USD` and `AGENT_MAX_STEPS`. Restart the queue worker after changes. Use a dedicated bot with only the credentials the pilot needs.

Grokked listens on loopback by default. Containers cannot reach the host's loopback via `127.0.0.1`. Establish an authenticated private path before enabling this driver; do not expose the API or VNC ports publicly. This AWS foundation deploys the **hub**, not the Grokked desktop fleet. Desktop provisioning and an authenticated VNC proxy are the next slice.

The pilot supports one trusted operator and one bot. Task visibility is isolated per user, but shared bot/browser credentials are not per-user authorization. Do not onboard unrelated users until bot ownership, scoped credentials and delegated authority exist. Domain and cost settings are instructions to Grokked, not a network sandbox or a guaranteed billing ceiling.

## AWS and deployment

See [the AWS runbook](docs/aws.md). CI needs no AWS credentials. Deployment stays disabled until the AWS repository variables are configured.

Merge to `main` → tests and Terraform validation → container build/smoke test → ECR commit image → digest deployment through SSM → HTTP health check. Infrastructure has a separate Actions plan/apply workflow. Initial AWS trust, state bucket and network must already exist.

EC2 is the first target for a single-host pilot. EKS, RDS, Bedrock/Nova adapters, agent-to-agent delegation, SSO, approval evidence, immutable audit events and automatic repair are **not implemented**. Add them against demonstrated workflow needs, with authority and recovery designed before autonomous changes.

## Recovery and limits

- `dispatch_unknown`, or `dispatching` after a worker crash, requires inspection of Grokked before another submission. Queue retries cannot bypass the dispatch guard.
- `blocked`, `sleeping`, and `paused_budget` are displayed; human replies, cancel and takeover use Grokked's own UI for now.
- Task and queue insertion share a transaction with the default database queue. Moving to Redis/SQS requires an outbox or equivalent durable handoff.
- SQLite lives on the host volume. No HA or automatic backup exists. Use synthetic data. Snapshot before changes; retained disks do not automatically attach to a replacement host.
- Deploys briefly stop services. Migration or health failure fails Actions without undoing database changes. Use additive migrations and the runbook recovery process.
- Logs go to CloudWatch; the task table is not an immutable audit ledger. This version makes no production compliance or PHI-handling claim.

## Sources

- [Laravel deployment](https://laravel.com/docs/13.x/deployment)
- [GitHub AWS OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Grokked bot](https://github.com/alnutile/grokked-bot)
