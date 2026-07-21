# RentifyX Platform Roadmap

**Current status:** see `.specs/project/STATE.md` for the actively-maintained, up-to-date state (this file describes original phase/epic intent, not day-to-day progress).

## Overall Goal

Deliver shared RentifyX platform infrastructure focusing on low cost, minimum viable security, and teardown-friendly testing.

## Milestones (as actually delivered, superseding the original EKS-based plan)

1. Terraform foundation and cost guardrails — done
2. Shared VPC and core network — done
3. ~~EKS on Fargate~~ — tried, removed 2026-07-17 (nothing needed a Kubernetes cluster)
4. Kafka: ~~Strimzi-on-EKS~~ → ~~MSK Serverless~~ → self-hosted (KRaft, single broker EC2), landed 2026-07-21 — see `.specs/features/self-hosted-kafka/`
5. Shared Cognito User Pool and SES sender identity — done
6. Free-tier observability with CloudWatch — done
7. Bootstrap/teardown scripts and documentation — in progress

## Epics

- Epic 1: Terraform Foundation, State & Cost Guardrails — done
- Epic 2: Network Foundation — done
- ~~Epic 3: EKS Cluster (Fargate)~~ — superseded, see ADR-001/ADR-002 in `docs/adr/`
- Epic 4: Kafka (self-hosted) — done, see `self-hosted-kafka` feature
- Epic 5: Shared Identity & Secrets (Cognito, SES) — done
- Epic 6: Observability (free tier) — done
- Epic 7: Bootstrap & Teardown Runbook — in progress (scripts exist, are skeletons — see `scripts/`)

## Short-term Items

- `modules/network` — done
- `modules/kafka` — done (self-hosted, rewritten 2026-07-21)
- `modules/api-gateway` — exists, not yet wired to either app service's backend
- `modules/cognito` — done
- `modules/ses` — done
- `modules/observability` — done
- `docs/adr/` — done (2 ADRs: EKS→removed, MSK Serverless→self-hosted)

## Notes

- The plan is built for a single `prod` environment; staging is deferred indefinitely, not phase 2 — no concrete plan to add it.
- Kafka went through three architectures before landing on the current one — see `docs/adr/001-shared-kafka-on-eks.md` and `docs/adr/002-msk-serverless.md` for the first two, and `.specs/features/self-hosted-kafka/` for the current (third) one. Read all three before proposing a fourth.
