# ADR-002: Replace self-hosted Kafka-on-EKS with MSK Serverless

**Status**: Accepted (2026-07-17)
**Supersedes**: [ADR-001](001-shared-kafka-on-eks.md)
**Related**: `modules/kafka/`, `modules/eks/` (removed)

## Context

ADR-001's design was never successfully applied: `terraform init`'s backend configuration was
broken (variable references inside a `backend "s3"` block, which Terraform disallows), and the
real S3 state bucket/DynamoDB lock table names had drifted from what the repo's own
`terraform.tfvars.example` claimed. Once those were fixed and a real `terraform plan` finally ran
end-to-end, `module.kafka`'s `kubernetes_manifest` resources (Strimzi `KafkaNodePool`/`KafkaTopic`
CRs) failed with a chicken-and-egg problem: they need a live EKS cluster's API to apply against,
but the EKS cluster is created in the same `terraform apply` — meaning a first-ever apply could
never succeed in one pass regardless of infra correctness, only via `-target` staging.

Separately, auditing what actually consumes EKS in this platform found: nothing does, except
Kafka. `rentifyx-identity-api` deploys itself via its own EC2 Terraform module, not EKS.
`rentifyx-communications-api` has no IaC at all yet (E-06 not started in that repo). ADR-001's
EKS cluster existed solely to host the Strimzi-managed Kafka broker.

## Decision

Remove `modules/eks/` entirely (cluster, IAM role, KMS-encrypted-secrets, restricted public
endpoint, control-plane logging — all real hardening work, now moot with no cluster to harden).
Replace `modules/kafka/`'s Strimzi-on-EC2-node-group setup with `aws_msk_serverless_cluster`
(SASL/IAM client authentication, its own security group, no node group, no Helm operator, no EBS
storage class).

This is **not** purely the cost-driven reversal ADR-001 explicitly said not to make ("should not
be revisited later purely on cost grounds") — MSK Serverless is not obviously cheaper than a single
`t4g.small` EC2 node (ADR-001 estimated ~$14/month for that; MSK Serverless has its own
per-partition/per-hour pricing that isn't necessarily lower at this project's volume). The actual
reasons are: (1) removing an entire unused compute platform (EKS) that nothing else in this
platform needs, and (2) removing the apply-ordering chicken-egg described above, so a first real
`terraform apply` can succeed without manual `-target` staging. The "learn real Kafka operational
patterns" goal from ADR-001 is weakened by this change (no more partition/broker/Strimzi-operator
hands-on ops), which is a real, acknowledged trade-off, not an oversight.

## Consequences

- **No more EC2/EBS/Strimzi operational surface.** MSK Serverless is fully AWS-managed — no node
  group to patch, no Helm chart to upgrade, no `kafka-gp3` StorageClass, no EBS CSI driver
  dependency (which was itself a Fargate-incompatibility workaround per ADR-001 — moot now).
- **Topics are no longer declared in Terraform.** MSK Serverless has no `aws_msk_topic` resource
  in the AWS provider and always auto-creates topics on first producer write (this can't be
  disabled). `rentifyx-communications-api`'s `RetryTopicChain` topic names (`notification-requested`
  + its `-retry-5s`/`-retry-1m`/`-retry-10m`/`-dlq` chain) still apply — they just get created
  implicitly instead of via an explicit `KafkaTopic` CR.
- **SASL/IAM replaces the "no auth, security-group-only" trust model.** ADR-001 relied on both
  producer and consumer running inside the same EKS cluster's network boundary with zero
  authentication. MSK Serverless requires SASL/IAM - `rentifyx-identity-api`'s
  `KafkaProducerFactory` and `rentifyx-communications-api`'s Kafka consumers both need an
  AWS-SigV4-based OAUTHBEARER token provider added (Confluent.Kafka's .NET client has no built-in
  MSK IAM support) before either can talk to the real broker in production. Not yet done in either
  repo as of this ADR.
- **Each service's own IAM role needs `module.kafka.client_iam_policy_json` attached** (in that
  service's own repo, not this one - this module only outputs the policy JSON, it doesn't own
  those roles). Not yet done in either repo as of this ADR.
- **SSM Parameter Store handoff convention (ADR-001's `/rentifyx/platform/kafka/bootstrap-servers`)
  is unchanged** - same path, now holding `aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam`
  instead of the old Strimzi-service DNS name.
