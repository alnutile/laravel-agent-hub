"""Send a deployment command without secrets in SSM payloads or workflow logs."""
import json
import os
import shlex
import subprocess
import time


def aws(*args):
    return subprocess.check_output(["aws", *args], text=True).strip()


image = os.environ["IMAGE"]
registry = image.split("/")[0]
q = shlex.quote
region = os.environ["AWS_REGION"]
command = "\n".join([
    "set -eu",
    f"aws ecr get-login-password --region {q(region)} | docker login --username AWS --password-stdin {q(registry)}",
    f"docker pull {q(image)}",
    "install -d -m 700 /opt/agent-hub",
    f"docker run --rm --entrypoint cat {q(image)} /var/www/html/ops/deploy.sh > /opt/agent-hub/deploy.sh",
    "bash /opt/agent-hub/deploy.sh " + " ".join(q(os.environ[k]) for k in ["IMAGE", "RUNTIME_SECRET_ARN", "AWS_REGION", "LOG_GROUP"]),
])
command_id = aws("ssm", "send-command", "--instance-ids", os.environ["INSTANCE_ID"],
                 "--document-name", "AWS-RunShellScript", "--timeout-seconds", "600",
                 "--parameters", json.dumps({"commands": [command], "executionTimeout": ["600"]}),
                 "--query", "Command.CommandId", "--output", "text")
print(f"SSM command: {command_id}", flush=True)
for _ in range(90):
    try:
        status = aws("ssm", "get-command-invocation", "--command-id", command_id,
                     "--instance-id", os.environ["INSTANCE_ID"], "--query", "Status", "--output", "text")
    except subprocess.CalledProcessError:
        status = "Pending"
    if status == "Success":
        print("Deployment succeeded.")
        break
    if status in {"Failed", "Cancelled", "TimedOut", "Cancelling"}:
        raise SystemExit(f"Deployment {status}. Inspect the SSM command and CloudWatch logs.")
    time.sleep(10)
else:
    raise SystemExit("Deployment status timed out; inspect SSM before retrying.")
