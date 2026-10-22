# AWS pilot runbook

## Bootstrap once

Use a sandbox AWS account through AWS SSO/profile. Never put access keys in GitHub or the repo. An account administrator must first provision:

1. An S3 state bucket with versioning, encryption, public access blocked and TLS-only access. Terraform uses `agent-hub/poc.tfstate` and `agent-hub/poc.tfstate.tflock`. Restrict access to state and the lock.
2. An existing VPC and private subnet with outbound access for AL2023 packages, ECR, Secrets Manager, CloudWatch and SSM. Current user data needs Internet/NAT egress; endpoints alone do not cover package downloads. No inbound ports or SSH keys are used.
3. The GitHub OIDC provider: `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
4. A dedicated Terraform provisioning role trusted by the exact `main` OIDC subject. Permissions must cover `infra/`: EC2/security groups/tags, ECR, Secrets Manager metadata, CloudWatch, SSM AMI parameter reads, creation/management/pass-role for `agent-hub-*` IAM roles/profile, and state/lock access. Scope provisioning with account permission boundaries and SCPs. This privileged bootstrap role is supplied by the account owner, not self-created by the app.

Both Actions roles must check audience and exact subject. Verify the repository's subject format: GitHub supports newer subjects with immutable owner/repo IDs and older name-only subjects. Do not add a wildcard to fix a failed login. Reported IDs here are owner `365385`, repository `1430214342`; verify the configured claim before selecting the subject.

Trust-condition shape:

```json
{
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": "EXACT_MAIN_BRANCH_SUBJECT"
  }
}
```

Terraform creates a deployment role that can publish to this ECR repository and send SSM commands only to this instance. SSM execution is root-equivalent on that host. Protect `main` and workflow edits with repository rules. These workflows do not add a manual approval gate; use existing organizational review policy. PR jobs never assume AWS roles.

## Repository variables

Settings → Secrets and variables → Actions → **Variables**:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | Deployment region |
| `AWS_OIDC_SUBJECT` | Verified exact main-branch subject |
| `AWS_TERRAFORM_ROLE_ARN` | Bootstrap provisioning role |
| `TF_STATE_BUCKET` | Versioned state bucket |
| `VPC_ID` | Existing VPC |
| `SUBNET_ID` | Private subnet with egress |

Run **Terraform infrastructure** on `main` with `apply=false` to inspect a plan, then `apply=true` to provision. Apply uses the exact saved plan from its run with S3 locking. Plans/state are not uploaded as public artifacts.

Add the outputs as variables:

| Variable | Terraform output |
| --- | --- |
| `ECR_URL` | `ecr_url` |
| `INSTANCE_ID` | `instance_id` |
| `RUNTIME_SECRET_ARN` | `runtime_secret_arn` |
| `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` |

Set `AWS_DEPLOY_ROLE_ARN` last, after populating the secret and checking the host is online in SSM. This enables deploys. ARNs/IDs are not secrets; API/model tokens are.

## Runtime secret

Terraform creates the secret container only. Populate its plaintext SecretString through AWS with the format in `ops/runtime.env.example`: a Docker env file, not JSON. Generate a new Laravel APP_KEY, keep it stable across releases, use `APP_DEBUG=false`, and start with `AGENT_DRIVER=demo`.

Do not commit the filled-in file, pass secrets as Terraform variables, or put them in Actions commands. EC2 retrieves the value into a mode-0600 temporary file under `/run`; the script removes it after Docker reads it. Host administrators can inspect container environments. Containers do not need AWS credentials; IMDSv2 is required.

HTTP binds only to `127.0.0.1:8080`. `SESSION_SECURE_COOKIE=false` is specifically for the local SSM tunnel. Before network-facing release, add TLS, set public APP_URL and secure cookies, configure trusted proxies, and review session/access controls.

## First deploy

Run **Test, build and deploy** on `main`, or merge a commit. Images use immutable commit tags resolved to digests. Re-runs reuse the existing digest.

With AWS CLI and Session Manager plugin on your computer:

```bash
aws ssm start-session --target YOUR_INSTANCE_ID \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Open http://localhost:8080. In another SSM shell session, provision an operator:

```bash
sudo docker exec -it --user www-data agent-hub-web php artisan hub:user you@example.com
```

Submit a demo task and refresh. Completion validates app → database queue → worker → history. Automated container checks cover startup, migrations and login; live Grokked and AWS need acceptance testing after access is configured.

## Operations and recovery

CloudWatch `/agent-hub/runtime` has `web`, `worker`, `scheduler` streams with 14-day retention. SSM command IDs appear in Actions. Deployment checks HTTP health, so verify a demo task also completes. Add disk/CPU and failed-job alarms before ongoing use.

SQLite lives in Docker volume `agent-hub-storage`. Back up using SQLite's online backup facility or stop writes before copying; a live database copy alone may be inconsistent. Create an encrypted EBS snapshot before infrastructure changes and restrict backup access.

Rollback application code by reverting through a PR and merging to `main`; Actions deploys the revert. Schema/data do not roll back. For migration failure, restore a verified backup or ship a forward fix via Actions. Avoid destructive migrations. Inspect `dispatching` tasks after interrupted dispatches.

`prevent_destroy` blocks accidental host replacement, including changed AMIs. Deliberate replacement requires a backup/restore plan and a reviewed guard change. Retained disks need manual restoration and continue costing money. Teardown is not a workflow: export/snapshot first and review a destroy plan through the normal operations process.

## Next boundaries

Put Grokked on a separate worker host/pool with its own role and network policy; desktop agents must not inherit hub credentials. Add private transport, per-user bot assignments, expiring delegation context and a session-authorized VNC proxy. Then evaluate EKS/fleet management and agent-to-agent handoffs. Bedrock inference and Nova Act are separate future adapters.
