# AWS pilot runbook

## Selected sandbox and bootstrap plan

The selected account is `415017828442`, region `us-east-1`. Live inspection on 2026-10-22 found no VPCs or subnets in that region. The GitHub OIDC provider exists with the required audience. GitHub reports the exact main subject as `repo:alnutile@365385/laravel-agent-hub@1430214342:ref:refs/heads/main`.

`infra/bootstrap/` prepares the missing prerequisites with an account guard:

- Dedicated versioned, encrypted, private, TLS-only state bucket `agent-hub-tfstate-415017828442-us-east-1`, protected against Terraform destruction.
- VPC `10.87.0.0/16`, NAT subnet `10.87.0.0/24` and private app subnet `10.87.1.0/24` in `us-east-1a`, with an Internet gateway, one zonal NAT gateway, EIP and separate route tables. The app host receives no public IP and no ingress rules.
- `agent-hub-terraform-provisioner` with exact main-branch OIDC trust. Permissions cover the app's named roles/profile, ECR, runtime secret metadata, log group, state/lock objects and tagged EC2 resources. It cannot change its own policy or bootstrap networking. Managing the app host and its role is still powerful authority: protect workflow edits and main-branch merges.

The existing `bh-demo-tfstate-415017828442` bucket contains other projects and lacks a TLS-only bucket policy; bootstrap leaves it untouched. No new AWS resources have been created by preparing the plan.

The NAT hourly rate retrieved from the AWS Pricing API for `us-east-1` is $0.045/hour. Combined with one public IPv4 at $0.005/hour, network baseline is approximately **$36.50 per 730-hour month**, plus NAT data processing, transfer and app resources (EC2, EBS, ECR, logs, secret and S3). See [AWS VPC pricing](https://aws.amazon.com/vpc/pricing/). Single-AZ NAT is sufficient for this pilot, not a highly available design. NAT charges continue even while the app instance is stopped.

An account administrator performs this one-time bootstrap after reviewing its saved plan:

```bash
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
# Apply only the reviewed plan after infrastructure approval.
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
```

Bootstrap begins with ignored local state because its own state bucket does not yet exist. Back up that local state securely, copy `infra/bootstrap/backend.local.tf.example` to ignored `infra/bootstrap/backend.local.tf`, then run `terraform -chdir=infra/bootstrap init -migrate-state` to migrate it to `agent-hub/bootstrap.tfstate`. Confirm the remote state exists before removing local backups. Application provisioning uses the separate `agent-hub/poc.tfstate` key through Actions. Never commit state or plan files.

Use bootstrap outputs to fill the repository variables below. The provisioning role deliberately has no access to bootstrap state. App code deployment continues exclusively through Actions. Bootstrap requires no merge or application deploy; running the app workflows on `main` will require the implementation PR to be reviewed and merged.

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

Submit a demo task and refresh. Completion validates app → database queue → worker → history. Automated container checks cover startup, migrations, login, task submission, duplicate suppression, database queue processing, demo completion and logout; live Grokked and AWS need acceptance testing after access is configured.

## Operations and recovery

CloudWatch `/agent-hub/runtime` has `web`, `worker`, `scheduler` streams with 14-day retention. SSM command IDs appear in Actions. Deployment checks HTTP health, so verify a demo task also completes. Add disk/CPU and failed-job alarms before ongoing use.

SQLite lives in Docker volume `agent-hub-storage`. Back up using SQLite's online backup facility or stop writes before copying; a live database copy alone may be inconsistent. Create an encrypted EBS snapshot before infrastructure changes and restrict backup access.

Rollback application code by reverting through a PR and merging to `main`; Actions deploys the revert. Schema/data do not roll back. For migration failure, restore a verified backup or ship a forward fix via Actions. Avoid destructive migrations. Inspect `dispatching` tasks after interrupted dispatches.

`prevent_destroy` blocks accidental host replacement, including changed AMIs. Deliberate replacement requires a backup/restore plan and a reviewed guard change. Retained disks need manual restoration and continue costing money. Teardown is not a workflow: export/snapshot first and review a destroy plan through the normal operations process.

## Next boundaries

Put Grokked on a separate worker host/pool with its own role and network policy; desktop agents must not inherit hub credentials. Add private transport, per-user bot assignments, expiring delegation context and a session-authorized VNC proxy. Then evaluate EKS/fleet management and agent-to-agent handoffs. Bedrock inference and Nova Act are separate future adapters.
