# Agent Hub continuation — 2026-10-22

## What the user is trying to accomplish

Build a proof of concept for an internal hub that makes AI and agent workflows usable by technical and nontechnical colleagues. The broader setting is exploration for a BetterHelp role, not an authorized BetterHelp production deployment. The user has not started that role and still needs discovery of actual processes, ownership and friction.

The key constraint is brownfield reality: speed up existing systems and remove friction, rather than create endless platforms. One interview example was UI releases slowed by legal checks. A useful pilot could assemble evidence and route review while preserving legal authority; flags should separate deploy from release, not bypass approval. AI can amplify existing process problems.

Longer-term ideas: a hub that routes requests, identifies owners/tickets, builds bounded automations, provisions managed agents and supports delegated work between agents. Logs and observability may eventually inform repair proposals. Autonomous production repair is not implemented or authorized by this prototype.

Laravel is the current control-plane choice. Reuse open-source foundations. AWS is the target platform, with Terraform for infrastructure and GitHub Actions for code deployments. EKS is an option when justified. Bedrock/Nova and Nova Act merit evaluation but are not implemented. Keep the desktop-agent execution plane separate from the hub's authority.

## Repository state

- Target: `https://github.com/alnutile/laravel-agent-hub` (public).
- Base `main`: `39995b3bd98cfe7dccc4da0ddb1fd98b651693eb`, originally only a README.
- Working branch: `feat/agent-hub-poc`.
- Main implementation commit: `42c22e5e24919fc9a356f6fb02315423b49b7dbd`; the handoff is committed after it.
- All code is committed locally and exported in `laravel-agent-hub-poc.bundle` for transfer.
- Initial publication was blocked by HTTP 403 because the GitHub app lacked access to the personal account. The user corrected the installation and branch creation succeeded. The implementation is being published through the connector on `feat/agent-hub-poc`; check the remote branch and PR for current publication and CI status. Connector-created commit IDs can differ from the original local bundle commits.
- No AWS resources were created. No AWS account, region, VPC/subnet, role or credentials have been supplied. Do not invent them.

## Implemented

Laravel 13 with PHP 8.4 development/CI, login and interactive operator provisioning, per-user task history, task deduplication by request UUID, transactionally queued task dispatch using the default database queue, demo execution, and a Grokked HTTP adapter.

Grokked API was reviewed at `alnutile/grokked-bot` commit `3ed6e4a55a80ae85b242a7b91b239a27ae0ed1ac`, especially `packages/daemon/src/http/runs.ts` and `src/runtime/container.ts`. It already has a Node daemon and Dockerized Linux desktops with a human takeover lock. Reuse that implementation rather than rebuilding it.

The adapter sends `POST /v1/runs` with bot_id, goal, new_thread=true, domain allowlist, max_steps and max_usd. It stores run.id and polls `GET /v1/runs/:id` through `hub:sync`. No automatic POST retry: ambiguous failures become `dispatch_unknown`; a process crash can leave `dispatching`, requiring reconciliation. Remote human-input/takeover/cancel is currently through Grokked itself.

The pilot is one trusted operator and one configured bot. Task display isolation is not per-user bot authorization. No desktop daemon/fleet is provisioned by this Terraform yet, and localhost routing from Docker to Grokked needs an authenticated private connection.

Infrastructure includes private EC2 in an existing VPC/subnet, ECR immutable tags, Secrets Manager secret metadata only, CloudWatch, host/deploy roles, SSM access, encrypted retained disk, and a host prevent_destroy guard. It relies on pre-existing OIDC trust/provider, a Terraform provisioning role, versioned state bucket and private network egress. Detailed inputs and recovery are in `docs/aws.md`.

Actions performs PHP checks, Terraform checks, image build/smoke test, then (main only, when variables enable it) ECR publish and digest deployment through SSM. A separate workflow plans/applies Terraform. Runtime values are pulled by the host from Secrets Manager, not embedded in code/state/Actions payloads.

## Verification performed

- `php artisan test`: **6 tests, 24 assertions, all passing**. Covers demo completion, remote status synchronization, auth/owner visibility, duplicate requests, uncertain dispatch suppression and frozen limits.
- Laravel Pint passes.
- Composer audit reported no advisories at implementation time.
- Terraform formatting passes. Provider initialization downloaded the signed AWS provider, but **full validate could not run in this environment**: the provider failed its startup handshake, and a later cached-package check reported a checksum mismatch. A fresh temporary initialization reproduced the startup failure. Do not call Terraform validated. Re-run init/validate locally or in Actions and investigate any reproducible provider problem.
- Workflow YAML and deployment Python parse; deployment Bash passes syntax check.
- Docker is unavailable in the original environment, so **image build and smoke test are unverified**. CI includes these checks, but CI has not run because push failed.
- Live Grokked dispatch, AWS plan/apply, OIDC login and live deployment remain untested.
- Git bundle verification passed before this handoff update; verify the final bundle when importing.

## Next actions for the local Codex session

1. Read this file, README and AWS runbook. Inspect current Git status and preserve any local user changes; do not reset or overwrite them.
2. Confirm the imported feature branch has all code. Use local PHP/Composer and Docker to run checks, build the image, apply migrations in a disposable container, check login and complete a demo task. Fix actual failures.
3. Run Terraform init with backend disabled and validate; do not apply anything while account/network details are missing. Pinning Actions/image dependencies to immutable digests and stronger infrastructure policy checks are sensible follow-up hardening before ongoing deployment.
4. Push `feat/agent-hub-poc` using the user's authenticated Git connection, open a PR, inspect Actions and fix CI. Public code is authorized; credentials must stay out of the repo. Do not claim it was published until verified.
5. Select AWS sandbox account/profile, region, existing VPC/subnet and bootstrap/state resources with the user. Use local AWS SSO or short-lived roles, never ask for credentials in chat. Populate the repository variables and runtime secret as documented, then deploy through Actions.
6. Demonstrate one end-to-end demo task on AWS. Then integrate a separate Grokked worker, verify its authority and transport boundaries, and demonstrate a bounded live task.

## Context outside this repo

The user uses SupaNet as a second brain and requested architecture notes in its BetterHelp collection. The previous session saved two notes in BetterHelpStack. They are optional extra context; all needed implementation state is here. Do not assume MCP connections, browser sessions or authentication automatically transfer between chat and local Codex.

The user offered to continue locally specifically to preserve context and unblock GitHub/AWS work. This handoff is the explicit continuity mechanism; a fresh local session should not pretend it has read the entire original conversation.
