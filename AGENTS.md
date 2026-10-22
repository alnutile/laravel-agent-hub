# Project guidance

Read `docs/HANDOFF.md` when resuming this project. `README.md` describes the implementation and `docs/aws.md` the deployment procedure.

- Reduce friction in existing workflows. Prefer one measurable end-to-end pilot over building a broad platform.
- This is a public, independent prototype. Never commit credentials, filled-in env files, Terraform state, real internal company data, or patient data.
- Manage infrastructure with Terraform. Deploy application code through GitHub Actions; do not manually deploy code to AWS hosts.
- Use GitHub OIDC for AWS authentication and Secrets Manager for runtime secrets. Keep desktop-agent authority separate from the hub's authority.
- Keep demo and real execution visibly distinct. Do not claim live AWS/Grokked validation based on mocked tests.
- Preserve dispatch reconciliation: Grokked POST submissions cannot be safely retried without upstream idempotency.
- EC2 is the first pilot target. EKS, Nova/Bedrock and agent delegation are future options, not current requirements to implement speculatively.
- Run relevant tests and format checks; update the handoff with material decisions, verification and remaining blockers.

Checks: `php artisan test`, `vendor/bin/pint --test`, `composer audit`, `terraform fmt -check -recursive infra`, `terraform -chdir=infra init -backend=false`, `terraform -chdir=infra validate`. CI also builds and smoke-tests the Docker image.
