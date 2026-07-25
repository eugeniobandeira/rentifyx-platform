#!/bin/bash
set -euo pipefail

# Install Docker
dnf install -y docker
systemctl enable --now docker

# Explicitly install and start the SSM Agent - confirmed 2026-07-25 via a real
# EC2 console log (no OOM this time, userdata completed cleanly in ~160s) that
# this AL2023 AMI resolution simply does not ship the agent pre-installed,
# despite AWS's own docs describing AL2023 as including it by default. Do not
# assume it's present; install and enable it unconditionally.
dnf install -y amazon-ssm-agent
systemctl enable --now amazon-ssm-agent

# Resolve this instance's own private IP at boot time via the EC2 instance
# metadata endpoint. Terraform can't template this value in (user_data can't
# self-reference the instance it belongs to before that instance exists), and
# it must be a real, reachable IP - not "localhost" - since clients connecting
# from identity-api/comms-api's own EC2 instances receive this address from
# the broker's metadata response and reconnect to it directly. Getting this
# wrong (e.g. leaving it as localhost) is the most common KRaft-in-Docker
# failure mode: the client connects once, then fails on broker metadata.
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Run Kafka in KRaft combined mode (broker + controller in one process, no
# Zookeeper) using Apache's official image. Single node, single broker -
# accepted trade-off documented in .specs/features/self-hosted-kafka/spec.md.
# PLAINTEXT only: the security group (VPC-CIDR-scoped) is the trust boundary.
# Explicit heap cap - confirmed the hard way 2026-07-24 that the JVM's
# default heap sizing on a t3.micro (1GiB) left no headroom for the OS,
# Docker daemon, or SSM Agent, causing OOM-driven instability (SSM Agent
# lost connection at boot and never recovered, broker itself only
# intermittently reachable). Even on the now-larger t3.small (2GiB), cap it
# explicitly rather than trust the image's default - a single-node
# dev/test broker has no need for a large heap.
# offsets/transaction replication factor pinned to 1 - confirmed 2026-07-25
# via a real deploy that Kafka's defaults (3) block __consumer_offsets from
# ever being created on a single-node broker ("Unable to replicate the
# partition 3 time(s)... only 1 broker(s) are registered"), which in turn
# means no consumer group can ever form (FindCoordinator never resolves) -
# every consumer silently never receives a single message, with no error on
# either the producer or consumer side.
docker run -d \
  --name kafka-broker \
  --restart unless-stopped \
  --memory=1g \
  -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://$LOCAL_IP:9092 \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
  -e KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
  -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
  -e KAFKA_HEAP_OPTS="-Xmx512m -Xms512m" \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  apache/kafka:latest
