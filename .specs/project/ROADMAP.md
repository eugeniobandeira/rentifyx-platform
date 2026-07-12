# RentifyX Platform Roadmap

## Overall Goal

Deliver shared RentifyX platform infrastructure in 18 days, focusing on low cost, minimum viable security, and teardown-friendly testing.

## Milestones

1. Terraform foundation and cost guardrails
2. Shared VPC and core network
3. EKS on Fargate
4. API Gateway + shared ALB via VPC Link
5. Shared Cognito User Pool and platform configuration
6. Free-tier observability with CloudWatch
7. Bootstrap/teardown scripts and final documentation

## Epics

- Epic 1: Terraform Foundation, State & Cost Guardrails
- Epic 2: Network Foundation
- Epic 3: EKS Cluster (Fargate)
- Epic 4: Edge: API Gateway & Shared Ingress
- Epic 5: Shared Identity & Secrets
- Epic 6: Observability (free tier) & Production
- Epic 7: Bootstrap & Teardown Runbook

## Immediate Priorities

1. Create the initial folder structure for modules and environment
2. Define remote Terraform backend and locking
3. Configure basic CI for `terraform fmt` and `terraform validate`
4. Document key decisions and constraints

## Short-term Items

- `modules/network`
- `modules/eks`
- `modules/api-gateway`
- `modules/cognito`
- `modules/observability`
- `prod/` with the main environment configuration
- `scripts/bootstrap.sh` and `scripts/teardown.sh`
- `docs/adr/`

## Notes

- The plan is built for a single `prod` environment; staging is deferred to phase 2.
- The fixed EKS control plane cost should be clearly communicated to the team to avoid surprises.
- The main savings come from selecting Fargate and a shared ALB.
