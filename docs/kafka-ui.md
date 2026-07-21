# Kafka UI Access

The self-hosted Kafka broker (see [`.specs/features/self-hosted-kafka/`](../.specs/features/self-hosted-kafka/)
— replaced AWS MSK Serverless 2026-07-21 to cut infra cost) has no built-in web UI. This runs
[kafbat-ui](https://github.com/kafbat/kafka-ui) — a real web UI — as a container on any EC2
instance in the same VPC (the broker's own instance, or either app repo's), reached over an
SSH tunnel.

Full spec/design: [`.specs/features/kafka-ui-access/`](../.specs/features/kafka-ui-access/).

## Start it

SSH onto either app repo's EC2 instance (identity-api's or communications-api's — both
carry the IAM permissions kafka-ui needs) and run the script:

```bash
scp -i <key> scripts/start-kafka-ui.sh ec2-user@<instance-public-dns>:/tmp/start-kafka-ui.sh
ssh -i <key> ec2-user@<instance-public-dns> "chmod +x /tmp/start-kafka-ui.sh && /tmp/start-kafka-ui.sh"
```

The script resolves the real broker address from SSM at run time — nothing is hardcoded.

## Access it

Open a local port-forward over SSH (no security group change needed — the SSH connection
itself carries the forwarded traffic):

```bash
ssh -L 8081:localhost:8081 -i <key> ec2-user@<instance-public-dns>
```

Then browse to `http://localhost:8081`. Close the SSH session to cut off access.

## Stop it

```bash
ssh -i <key> ec2-user@<instance-public-dns> "docker rm -f kafka-ui"
```

## Notes

- Not Terraform-managed. It's a plain Docker container started on demand, torn down along
  with whichever EC2 instance it happens to be running on (e.g. via `terraform destroy`).
- No new security group rule is created or needed — access is entirely through the SSH
  tunnel, same access path SSH to the instance already implies.
- Re-running `start-kafka-ui.sh` is safe — it removes any existing `kafka-ui` container
  first.
