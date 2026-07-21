#!/bin/bash
set -euo pipefail

# Install Docker
dnf install -y docker
systemctl enable --now docker

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
docker run -d \
  --name kafka-broker \
  --restart unless-stopped \
  -p 9092:9092 \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES=broker,controller \
  -e KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093 \
  -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://$LOCAL_IP:9092 \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093 \
  -e KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT \
  -e KAFKA_AUTO_CREATE_TOPICS_ENABLE=true \
  apache/kafka:latest
