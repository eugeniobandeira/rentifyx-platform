# ADR-001: Self-hosted Kafka on a dedicated EC2 node group

**Status**: Accepted (2026-07-15)
**Related**: `.specs/features/shared-kafka-eks/spec.md`, `.specs/features/shared-kafka-eks/design.md`

## Context

`rentifyx-identity-api` needs to become a Kafka producer (`NotificationRequested` events,
replacing its current direct-SES email sending — see that repo's
`.specs/features/outbox-kafka-notifications/spec.md`). `rentifyx-communications-api` already
consumes that exact topic shape and has a full retry/DLQ topic chain built around it (F-09). But
neither service has ever provisioned a real Kafka broker for production — both only run a local
Aspire dev container. Since this is cross-service infrastructure, not owned by either business
service, it belongs in this platform repo.

Two sub-decisions had to be made:

### 1. Managed (MSK) vs. self-hosted

AWS MSK Serverless starts at roughly $60-90/month minimum; MSK provisioned is more. A single
self-hosted broker on a small EC2 instance costs roughly $14/month (compute + EBS). MSK was
rejected on cost — this repo's `PROJECT.md` already commits to a cost-minimized architecture
(Fargate over EC2, single shared NAT, CloudWatch-only observability), and MSK doesn't fit that.

The project's stated goal for wanting Kafka at all is to learn Kafka's real operational patterns
(partitions, consumer groups, the retry-topic-chain reliability engineering already built in
comms-api's F-09) — confirmed explicitly with the project owner on 2026-07-15 — not to solve
notification delivery by the cheapest possible means. A fully-managed alternative (SNS/SQS, which
would make F-09's hand-built retry-topic-chain unnecessary and cost near-zero at this volume) was
considered and explicitly rejected for this reason. This is a deliberate, informed trade-off, not
an oversight — it should not be revisited later purely on cost grounds.

### 2. Where does Kafka's storage live, given this repo's EKS runs on Fargate?

`PROJECT.md`'s stated architecture is "EKS on Fargate to eliminate idle EC2 instance costs." This
conflicts directly with Kafka's storage requirements:

- **EBS cannot mount on Fargate pods at all.** The EBS CSI *controller* can run on Fargate, but
  the EBS CSI *node* DaemonSet (which actually attaches a volume to a pod) can only run on EC2
  instances. This is an architectural limitation, not a config gap. ([AWS EKS docs — EBS CSI
  driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html))
- **EFS (the storage type Fargate does support) is a documented poor/unsafe fit for Kafka
  specifically**, not just a performance trade-off. NFS-backed Kafka has a reproducible failure
  mode — the "silly rename" issue crashes the broker during partition reassignment, which is
  routine cluster operation, not a rare edge case. Kafka's own community guidance is to avoid
  NAS/NFS storage outright. ([KAFKA-13995 — Does Kafka support NFS? Is it recommended in
  Production?](https://issues.apache.org/jira/browse/KAFKA-13995), [Cloudera Kafka Best
  Practices](https://community.cloudera.com/t5/Community-Articles/Kafka-Best-Practices/ta-p/249371))

## Decision

Provision a small, dedicated EC2 managed node group (`t4g.small`, Graviton/ARM64, single node —
min=max=desired=1) alongside the existing Fargate profile, solely for Kafka. Kafka runs in KRaft
mode (no ZooKeeper) with a single broker (no replication), deployed via the Strimzi Kafka Operator
(Helm chart `oci://quay.io/strimzi-helm/strimzi-kafka-operator`, version 0.45.0). Storage is a
15Gi `gp3` EBS volume via a dedicated `aws-ebs-csi-driver` EKS addon and `kafka-gp3` StorageClass,
attached to that node group only (`nodeAffinity` on `workload=kafka`).

Broker bootstrap address is published to SSM Parameter Store at
`/rentifyx/platform/kafka/bootstrap-servers`, following this repo's existing SSM convention for
cross-repo config handoff (avoids granting `terraform_remote_state` read access across repos).
Both `rentifyx-identity-api` and `rentifyx-communications-api` read from this path in production.

No SASL/mTLS is configured — Kafka traffic is restricted to the cluster's security group only
(self-referencing ingress rule, port 9092), since both producer and consumer run inside the same
cluster's network boundary.

## Consequences

- **~$14/month recurring EC2 + EBS cost**, breaking this repo's stated "no idle EC2" goal. Accepted
  explicitly, in writing, as the cost of having a real (not simulated) Kafka deployment for
  learning purposes — see Context above.
- **Single point of failure**: one broker, no replication. Acceptable for this project's actual
  traffic volume (low-volume transactional email events, not high-throughput streaming). Both
  producer (`OutboxPublisher` retry) and consumer (`NotificationRequestedConsumer` reconnect
  logic) already tolerate broker unavailability from their own retry logic — no new handling
  required on either side for this.
- **A new operational surface**: this is the first EC2 node group and the first Helm-managed
  workload in this repo (everything else is either Fargate-scheduled or a plain AWS resource).
  Node/pod health for this workload is not covered by anything beyond what
  `modules/observability`'s existing CloudWatch log group already captures — no dedicated
  alerting was added (see spec.md Out of Scope).
- **First real SSM-publish implementation in this repo.** ADR-005 (referenced in
  `rentifyx-plan.md.md`) described this convention but nothing had implemented it until this
  feature — worth checking that other planned shared config eventually follows the same pattern
  established here (`/rentifyx/platform/kafka/*`).
