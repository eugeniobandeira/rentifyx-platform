#!/bin/bash
# Starts (or restarts) a kafbat-ui container on this host, connecting to the
# self-hosted Kafka broker (PLAINTEXT, no auth - see
# ../.specs/features/self-hosted-kafka/ for why MSK Serverless was replaced).
#
# Must run on an EC2 instance inside rentifyx-platform's VPC (identity-api's,
# communications-api's, or the Kafka broker instance itself) - the broker's
# private IP is only reachable from within the VPC.
# See ../.specs/features/kafka-ui-access/ for the full spec/design and
# ../docs/kafka-ui.md for the SSH-tunnel access instructions.

set -euo pipefail

AWS_REGION="${AWS_REGION:-sa-east-1}"
BOOTSTRAP_SERVERS_SSM_PATH="/rentifyx/platform/kafka/bootstrap-servers"
KAFKA_UI_PORT="${KAFKA_UI_PORT:-8081}"

echo "Resolving Kafka bootstrap servers from SSM (${BOOTSTRAP_SERVERS_SSM_PATH})..."
BOOTSTRAP_SERVERS=$(aws ssm get-parameter \
  --name "$BOOTSTRAP_SERVERS_SSM_PATH" \
  --with-decryption \
  --region "$AWS_REGION" \
  --query "Parameter.Value" \
  --output text)

echo "Removing any existing kafka-ui container..."
docker rm -f kafka-ui 2>/dev/null || true

echo "Starting kafka-ui on port ${KAFKA_UI_PORT}..."
docker run -d \
  --name kafka-ui \
  --restart unless-stopped \
  -p "${KAFKA_UI_PORT}:8080" \
  -e KAFKA_CLUSTERS_0_NAME=rentifyx \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS="$BOOTSTRAP_SERVERS" \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL=PLAINTEXT \
  ghcr.io/kafbat/kafka-ui:latest

echo "kafka-ui started. Open an SSH tunnel from your local machine:"
echo "  ssh -L ${KAFKA_UI_PORT}:localhost:${KAFKA_UI_PORT} -i <key> ec2-user@<this-host-public-dns>"
echo "Then browse to http://localhost:${KAFKA_UI_PORT}"
