# Feature Spec: Shared Kafka Cluster on EKS

## Status

Draft — unblocks a cross-service integration: `rentifyx-identity-api` needs to become a Kafka
producer (`NotificationRequested` events, see its own
`.specs/features/outbox-kafka-notifications/spec.md`) and `rentifyx-communications-api` already
consumes that exact topic shape, but neither service has ever provisioned a real broker for
production — both only run Kafka as a local Aspire dev container. This repo is the natural home
for it since it's cross-service infrastructure, not owned by either business service.

## Problem

No Kafka/MSK/messaging infrastructure exists anywhere in this repo, and it isn't on this repo's
own roadmap (`ROADMAP.md`'s Epics are Network/EKS/API-Gateway/Cognito/Observability only). Two
consumer services need a shared broker before their integration can be tested or shipped to
production.

## Decisions (confirmed with user, 2026-07-15)

- **Not AWS MSK.** Rejected as managed-service cost, inconsistent with this repo's explicit
  cost-minimization philosophy (Fargate over EC2, single shared NAT, CloudWatch-only observability
  — see `PROJECT.md` Objective/Constraints).
- **Self-hosted Kafka on the shared EKS cluster**, via Helm chart (Strimzi or Bitnami — pick one at
  design time; Strimzi is Kafka-native/operator-based and generally the better-maintained choice
  for KRaft mode, but confirm current chart maturity before committing).
- **Broker connection info published via SSM Parameter Store**, under `/rentifyx/platform/*`,
  matching this repo's existing ADR-005 convention (SSM instead of `terraform_remote_state`
  across repos — avoids granting cross-repo state read access). Both `rentifyx-identity-api` and
  `rentifyx-communications-api` read the broker address from there in production; local dev in
  both repos keeps using their own Aspire Kafka containers, unaffected.

## Requirements

| ID | Requirement | Source | Notes |
|---|---|---|---|
| R-01 | New `modules/kafka/` Terraform module deploying a Kafka Helm release onto the existing shared EKS cluster (`module.eks`) | Core deliverable | Must not require its own dedicated node group cost if avoidable — investigate whether the existing Fargate profile can host it (see R-02, this is the open architectural risk) |
| R-02 | **Design-time risk to resolve before Tasks**: EKS in this repo runs on Fargate (`PROJECT.md` — "EKS on Fargate to eliminate idle EC2 instance costs"). Fargate pods do not support EBS-backed `PersistentVolumeClaim`s — only ephemeral storage or EFS. Kafka brokers need durable, low-latency disk for log segments; EFS (NFS-based) is a well-known poor fit for Kafka's write pattern. | Discovered during this spec's own research — `modules/eks/main.tf` and `PROJECT.md` confirm Fargate-only today | Must resolve at design time: either (a) add a small dedicated EC2 node group alongside the Fargate profile just for the Kafka StatefulSet (breaks "no idle EC2" but may be unavoidable), (b) accept EFS-backed storage with a documented performance caveat (acceptable for a low-volume study-project workload — transactional email + eventual campaign fan-out, not high-throughput streaming), or (c) run Kafka in KRaft mode with a single broker (no replication) to minimize footprint. Do not default silently to any of these — pick explicitly and document the trade-off as a new ADR (see R-05). |
| R-03 | Topic provisioning: `notification-requested` (+ comms-api's existing retry-chain topics — `-retry-5s`/`-retry-1m`/`-retry-10m`/`-dlq`, see that repo's F-09) created declaratively (Helm values, Strimzi `KafkaTopic` CRD, or a one-time init job) rather than relying on broker auto-create | comms-api's F-09 already defines this exact topic chain — this module should provision what that consumer already expects, not redesign it | Read `rentifyx-communications-api/.specs/features/e04-f09-reliability/design.md` for the authoritative topic list before implementing |
| R-04 | Publish broker bootstrap address (and any auth/SASL config, if added — see Out of Scope) to SSM under a documented `/rentifyx/platform/kafka/*` path | ADR-005 convention (SSM, not remote state) | Exact key names — coordinate with both consumer repos' config-reading code (`IConfiguration`-sourced per identity-api's R-10) so this isn't designed in isolation and then mismatched |
| R-05 | New ADR documenting the Fargate-vs-Kafka storage decision (R-02) and the MSK-vs-self-hosted decision (already made above, but undocumented) | `docs/adr/README.md` is currently just a placeholder — this would be among the first real ADRs in this repo | Follow this repo's existing ADR numbering/format once any prior ADRs are actually written down (currently only referenced by number in `rentifyx-plan.md.md`, never filed as actual documents — flag that gap too, out of this spec's scope to fully backfill) |
| R-06 | Update `prod/main.tf` to compose the new `kafka` module after `eks`, mirroring how `api_gateway`/`observability` already depend on `module.eks` | Consistency with existing composition pattern | Single flat `prod/terraform.tfstate` today (not per-module) — confirm this module doesn't need its own state before deviating from that pattern |

## Out of Scope

| Item | Reason |
|---|---|
| SASL/mTLS authentication between brokers and producer/consumer services | Both consumer services run inside the same shared EKS cluster's network boundary (or will, once deployed there) — cluster-internal traffic; revisit if either service ever needs to reach the broker from outside the VPC |
| Multi-broker replication / high availability | Cost-minimization philosophy (single NAT, single environment) extends here — a single-broker KRaft setup is acceptable for this project's actual traffic volume; document as a known limitation, not silently assumed permanent |
| Schema registry | Neither consumer service uses Avro/Protobuf — both use plain JSON (`System.Text.Json`) message bodies per comms-api's existing `NotificationRequested` handling |
| Monitoring/alerting on the Kafka cluster itself beyond what `modules/observability`'s existing CloudWatch log group already captures | Out of first-phase scope per `PROJECT.md`'s own "Excluded" list philosophy (no paid observability tooling) |

## Ordering rationale

1. R-02 (Fargate storage decision) — must be resolved first, it changes what R-01 even builds; do not start Tasks until this has an explicit answer.
2. R-05 (ADR) — write alongside R-02's resolution, not after — the decision and its documentation should land together.
3. R-01, R-06 (module + composition) — the actual Terraform.
4. R-03 (topic provisioning) — needs R-01 done; requires reading comms-api's F-09 design doc first.
5. R-04 (SSM publish) — last, since its exact shape depends on what both consumer repos' config code expects — coordinate before finalizing key names.
