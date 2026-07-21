# Self-Hosted Kafka (replace AWS MSK Serverless) Specification

## Problem Statement

AWS MSK Serverless (`module.kafka`) bills per cluster-hour + per partition-hour + storage, which is expensive to keep running for a study project that is only spun up occasionally to test/demo the cross-repo notification flow (`rentifyx-identity-api` → Kafka → `rentifyx-communications-api` → SES). A single-broker, self-hosted Kafka (KRaft mode, no Zookeeper) running as a Docker container on a small dedicated EC2 instance costs a fraction of MSK Serverless and is sufficient for this project's scale and reliability needs.

## Goals

- [ ] Replace `rentifyx-platform`'s `module.kafka` (MSK Serverless) with a self-hosted, single-broker Kafka (KRaft mode) on a new dedicated EC2 instance owned by `rentifyx-platform`
- [ ] `rentifyx-identity-api`'s producer (`KafkaProducerFactory`, `OutboxPublisher`) and `rentifyx-communications-api`'s consumers (`KafkaConsumerFactory`, `NotificationRequestedConsumer`, `RetryTopicConsumer`, `DlqObserverHostedService`) switch from SASL/IAM (`AWSMSKAuthTokenGenerator` + OAUTHBEARER) to a auth mechanism the self-hosted broker actually supports
- [ ] `kafbat-ui` continues to work against the new broker (topic creation/management, no regression from the current MSK-backed setup)
- [ ] Bootstrap servers address is published the same way as today (SSM Parameter Store, consumed via `terraform_remote_state`/`data.aws_ssm_parameter` by both app repos) so no app-repo wiring pattern changes beyond the auth mechanism

## Out of Scope

| Feature | Reason |
| --- | --- |
| Multi-broker replication / HA | Single broker is an accepted, already-discussed trade-off for a study project — infra is destroyed between test sessions anyway |
| TLS between broker and clients | SASL/PLAIN or PLAINTEXT within the VPC is sufficient; the VPC boundary is the trust boundary here, matching the project's existing security posture (no public broker exposure) |
| Migrating existing MSK data | No production data exists; infra is destroyed/recreated for each test session, so there's nothing to migrate |
| Removing `kafka-ui-access` feature's SSH-tunnel access pattern | Unrelated — that feature's access model (SSH tunnel to reach kafbat-ui) is unaffected by which broker is behind it |

---

## User Stories

### P1: Broker runs cheaply and is reachable from both app repos ⭐ MVP

**User Story**: As the project owner, I want Kafka to run on a cheap, self-hosted broker instead of MSK Serverless, so that leaving infra up for testing doesn't rack up per-partition-hour charges.

**Why P1**: This is the entire point of the feature — cost reduction is the only driver.

**Acceptance Criteria**:

1. WHEN `rentifyx-platform`'s Terraform is applied THEN it SHALL provision one small EC2 instance (e.g. `t3.micro`/`t3.small`) running Kafka in KRaft mode via Docker, in the platform VPC's private subnet
2. WHEN the broker starts THEN it SHALL create/expose a `PLAINTEXT` listener reachable from both app repos' EC2 instances within the same VPC — no SASL credential, trust boundary is the security group (decided 2026-07-21: simplicity over defense-in-depth, consistent with this being a study-project broker with no persistent/sensitive data)
3. WHEN `rentifyx-platform`'s Terraform apply completes THEN it SHALL publish the broker's bootstrap address to the same SSM parameter path both app repos already read (`kafka_ssm_parameter_path` output), so no consuming-side wiring changes
4. WHEN MSK Serverless resources (`module.kafka`'s `aws_msk_serverless_cluster`, its IAM policies) are removed THEN `terraform plan` SHALL show a clean destroy/replace with no orphaned references elsewhere in the repo

**Independent Test**: Apply platform's Terraform alone, SSH into the new broker EC2, run `kafka-topics.sh --bootstrap-server localhost:9092 --list` and confirm the broker responds.

---

### P2: Producer/consumer code authenticates correctly against the new broker

**User Story**: As a developer, I want `rentifyx-identity-api`'s producer and `rentifyx-communications-api`'s consumers to connect to the self-hosted broker without code depending on AWS IAM, so the apps work the same regardless of which broker backs them.

**Why P2**: Required for the flow to actually work end-to-end, but distinct from the infra change itself — this is app-repo code, done after the broker exists.

**Acceptance Criteria**:

1. WHEN `KafkaProducerFactory`/`KafkaConsumerFactory` build a client config THEN they SHALL set `SecurityProtocol = SecurityProtocol.Plaintext` (no SASL mechanism, no credential) instead of `AWSMSKAuthTokenGenerator`/OAUTHBEARER
2. WHEN the `AWS.MSK.Auth` NuGet package is no longer used by either app repo THEN it SHALL be removed from `Directory.Packages.props`/the referencing `.csproj`
3. WHEN a message is produced by identity-api's `OutboxPublisher` THEN it SHALL be consumed by comms-api's `NotificationRequestedConsumer` end-to-end (same flow already proven against MSK, now against the self-hosted broker)

**Independent Test**: Run the existing end-to-end manual test (register a user → email arrives) against the new broker.

---

### P3: kafbat-ui keeps working for topic management

**User Story**: As the project owner, I want to keep using kafbat-ui to inspect/manage topics after the broker migration, so I don't lose the visibility the `kafka-ui-access` feature already gave me.

**Why P3**: Nice-to-have continuity, not blocking — topics can be created manually via `kafka-topics.sh` if kafbat-ui integration slips.

**Acceptance Criteria**:

1. WHEN kafbat-ui is started (per `docs/kafka-ui.md`'s existing runbook) THEN it SHALL connect to the self-hosted broker with no SASL config (plaintext) instead of `IAMLoginModule`

**Independent Test**: Start kafbat-ui per the existing runbook, confirm it lists topics from the self-hosted broker.

---

## Edge Cases

- WHEN the broker EC2 instance is replaced (AMI update, manual reboot) THEN topics/messages SHALL be lost (no persistent EBS volume required for this scope) — acceptable since infra is destroyed/recreated per test session anyway; document this clearly so it isn't mistaken for a bug later
- WHEN both app repos' EC2 security groups need to reach the new Kafka EC2's port THEN the security group rule SHALL be scoped to the VPC CIDR or the specific app security groups, not `0.0.0.0/0` — this is the entire trust boundary now that there's no SASL credential

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| KAFKA-01 | P1: Broker runs cheaply and is reachable | Design | Pending |
| KAFKA-02 | P1: Broker runs cheaply and is reachable | Design | Pending |
| KAFKA-03 | P1: Broker runs cheaply and is reachable | Design | Pending |
| KAFKA-04 | P1: Broker runs cheaply and is reachable | Design | Pending |
| KAFKA-05 | P2: Producer/consumer auth | Design | Pending |
| KAFKA-06 | P2: Producer/consumer auth | Design | Pending |
| KAFKA-07 | P2: Producer/consumer auth | Design | Pending |
| KAFKA-08 | P3: kafbat-ui continuity | Design | Pending |

**Coverage:** 8 total, 0 mapped to tasks, 8 unmapped ⚠️ (expected pre-Design)

---

## Success Criteria

- [ ] `rentifyx-platform`'s Terraform apply provisions the self-hosted broker with no MSK Serverless resources remaining
- [ ] Both app repos build and pass existing tests with `AWS.MSK.Auth` removed
- [ ] End-to-end flow (register → Kafka → email) confirmed working against the self-hosted broker, same as it was confirmed against MSK
- [ ] kafbat-ui confirmed working against the new broker
