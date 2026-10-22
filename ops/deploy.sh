#!/usr/bin/env bash
set -euo pipefail
# Runs as root on the target EC2 instance via SSM. Never enable shell tracing.
image=${1:?image digest required}
secret_arn=${2:?runtime secret ARN required}
region=${3:?AWS region required}
log_group=${4:?CloudWatch log group required}
[[ "$image" =~ ^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/agent-hub@sha256:[a-f0-9]{64}$ ]] || exit 2
install -d -m 700 /opt/agent-hub
env_file=$(mktemp /run/agent-hub-env.XXXXXX)
chmod 600 "$env_file"
trap 'rm -f "$env_file"' EXIT
aws secretsmanager get-secret-value --region "$region" --secret-id "$secret_arn" --query SecretString --output text > "$env_file"
# SecretString is a Docker-compatible env file, not JSON; it never enters Terraform state.
grep -q '^APP_KEY=base64:' "$env_file" || { echo 'Runtime APP_KEY missing'; exit 1; }
docker volume create agent-hub-storage >/dev/null
docker run --rm --user 0 --entrypoint sh -v agent-hub-storage:/var/www/html/storage "$image" -c \
    'mkdir -p storage/app storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs; touch storage/app/hub.sqlite; chown -R www-data:www-data storage'
for service in web worker scheduler; do docker rm -f "agent-hub-$service" >/dev/null 2>&1 || true; done
common=(--env-file "$env_file" -v agent-hub-storage:/var/www/html/storage --security-opt no-new-privileges:true)
docker run --rm --user www-data "${common[@]}" "$image" php artisan migrate --force
logging=(--log-driver awslogs --log-opt "awslogs-region=$region" --log-opt "awslogs-group=$log_group")
docker run -d --name agent-hub-web --restart unless-stopped "${common[@]}" "${logging[@]}" --log-opt awslogs-stream=web \
    -p 127.0.0.1:8080:80 "$image" >/dev/null
docker run -d --name agent-hub-worker --restart unless-stopped --user www-data "${common[@]}" "${logging[@]}" --log-opt awslogs-stream=worker \
    "$image" php artisan queue:work --sleep=2 --tries=1 --timeout=30 >/dev/null
docker run -d --name agent-hub-scheduler --restart unless-stopped --user www-data "${common[@]}" "${logging[@]}" --log-opt awslogs-stream=scheduler \
    "$image" php artisan schedule:work >/dev/null
for attempt in {1..30}; do
    if curl --fail --silent http://127.0.0.1:8080/up >/dev/null; then
        printf '%s\n' "$image" > /opt/agent-hub/current-image
        echo 'Agent Hub deployed and HTTP health check passed.'
        exit 0
    fi
    sleep 2
done
echo 'Health check failed. Inspect CloudWatch; this deployment was not recorded as healthy.' >&2
exit 1
