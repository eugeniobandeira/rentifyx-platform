# rentifyx-platform — Implementation Plan (low-cost version)

**Shared infrastructure** for the RentifyX ecosystem: VPC, EKS, API Gateway, and Cognito. Revised for the lowest possible monthly cost — single environment, single NAT, Fargate instead of idle EC2 nodes, one shared Ingress instead of one Load Balancer per service.

**Stack:** Terraform (S3 backend + DynamoDB lock) · VPC (1 shared NAT) · EKS + Fargate profile + IRSA + AWS Load Balancer Controller · API Gateway (HTTP API) + VPC Link (points to 1 shared ALB) · Shared Cognito User Pool · OTEL Collector → CloudWatch (free tier) · GitHub Actions with tflint/checkov · SSM Parameter Store (`/rentifyx/platform/*`) · AWS Budgets

**Estimate:** ~18 days · 7 epics · 62 tasks (adjusted)

---

## What changed in this revision

| Item | Before | Now | Estimated savings |
|---|---|---|---|
| Environments | prod + staging | **prod only** | ~50% of everything below |
| NAT Gateway | 1 per AZ (3 total) | **1 shared** | ~$64/month |
| Cluster compute | EC2 node group 24/7 | **Fargate profile** (pay per running pod) | Compute cost drops close to zero when idle |
| Load balancing | 1 NLB per microservice | **1 shared ALB/Ingress** | ~$16/month saved per service |
| Observability | OTEL + Datadog agent | **OTEL → CloudWatch (free tier)** | Eliminates Datadog license cost |
| WAF, custom domain (ACM/Route53) | In v1.0.0 | **Deferred (Phase 2)** | ~$6–10/month deferred |
| VPC Flow Logs | Enabled | **Deferred (Phase 2)** | CloudWatch ingestion cost deferred |
| Budget alert | Missing | **Added (AWS Budgets)** | Visibility before any bill surprise |

The one fixed cost that can't be removed while keeping managed EKS is the **control plane (~$73/month)** — it's charged regardless of usage. If you ever want to cut that too, the alternative is k3s on a single EC2 instance, but you've already decided to keep managed EKS.

---

## Epic 1 — Terraform Foundation, State & Cost Guardrails
**Days 1–3**
🎯 Remote state with locking, CI with security gates, and a budget alert before any network resource exists

### Feature: Backend & Module Structure

**US-001** — As a dev, I want remote state with locking so concurrent applies never conflict
- [ ] T-001 (D1) Create S3 bucket for state (versioning + SSE-KMS encryption)
- [ ] T-002 (D1) Create DynamoDB table for state locking (rentifyx-tf-locks)
- [ ] T-003 (D1) Define backend.tf — **single environment (prod)**, no duplication for staging
- [ ] T-004 (D1) Module structure: modules/{network, eks, api-gateway, cognito, observability}
- [ ] T-005 (D1) Single environments/prod directory (staging goes to backlog — Phase 2)

**US-002** — As a tech lead, I want CI gates for Terraform so nothing ships without validation
- [ ] T-006 (D2) GitHub Actions: terraform fmt -check + validate on every PR
- [ ] T-007 (D2) GitHub Actions: terraform plan auto-commented on the PR
- [ ] T-008 (D2) Manual approval gate before terraform apply on merge to main
- [ ] T-009 (D3) Add tflint + checkov as a security step in CI
- [ ] T-010 (D3) ADR-001: single environment, one state per layer (network, eks, edge, identity-shared)

### Feature: Cost Guardrails *(new)*

**US-013** — As a dev, I want to be warned before the AWS bill surprises me
- [ ] T-056 (D3) AWS Budgets: alert at 50%/80%/100% of a defined monthly ceiling
- [ ] T-057 (D3) Cost allocation tags on all resources (Project=RentifyX, Environment=prod, Service=platform)
- [ ] T-058 (D3) SNS topic + email subscription for billing alarm notification

---

## Epic 2 — Network Foundation
**Days 4–6**
🎯 VPC with 1 shared NAT — accepts a single point of failure on the NAT in exchange for ~$64/month savings

### Feature: VPC & Subnets

**US-003** — As a dev, I want a VPC with public and private subnets across multiple AZs
- [ ] T-011 (D4) aws_vpc module (planned CIDR, DNS support enabled)
- [ ] T-012 (D4) **1 shared NAT Gateway** across all 3 AZs (not 1 per AZ)
- [ ] T-013 (D4) Private subnets across 3 AZs for the cluster (Fargate spreads pods across them)
- [ ] T-014 (D4) Route tables + public/private associations
- [ ] T-016 (D5) ADR-002: single NAT — saves ~$64/month, accepts downtime if the NAT's AZ goes down

**US-004** — As a security engineer, I want baseline security groups for controlled internal traffic
- [ ] T-017 (D6) Security group for Fargate pods (internal cluster communication)
- [ ] T-018 (D6) Security group for the shared ALB
- [ ] T-019 (D6) Security group for VPC Link ENIs
- [ ] T-020 (D6) Document CIDR plan (avoid overlap with future VPN/on-prem)

> **Backlog / Phase 2:** VPC Flow Logs (deferred — CloudWatch ingestion cost only justifiable once there's real production traffic).

---

## Epic 3 — EKS Cluster (Fargate)
**Days 7–10**
🎯 EKS cluster with no idle EC2 node — Fargate charges per running pod, not per instance kept on 24/7

### Feature: Cluster Provisioning

**US-005** — As a dev, I want an EKS cluster provisioned via Terraform with no idle compute cost
- [ ] T-021 (D7) aws_eks_cluster module (pinned version, private endpoint)
- [ ] T-022 (D7) OIDC provider to enable IRSA
- [ ] T-023 (D8) **Fargate profile** (default + kube-system namespaces) — replaces EC2 node group
- [ ] T-024 (D8) Fargate-compatible core add-ons: CoreDNS (patched to run on Fargate), kube-proxy
- [ ] T-025 (D9) AWS Load Balancer Controller via helm_release (Fargate-compatible)
- [ ] T-026 (D9) ADR-003: Fargate profile instead of managed node group — eliminates idle EC2 cost, accepts higher per-pod cold start
- [ ] T-027 (D10) Kubeconfig generation script + docs for local dev access

**US-006** — As a dev, I want a reusable IRSA pattern so each service gets its own role
- [ ] T-028 (D10) Parametrized IRSA module (takes service name + policy)
- [ ] T-029 (D10) Example IRSA binding for the identity-api service account
- [ ] T-030 (D10) Publish OIDC issuer URL + cluster name to SSM for service repos to consume

---

## Epic 4 — Edge: API Gateway & Shared Ingress
**Days 11–13**
🎯 A single HTTP entry point for all microservices — without multiplying Load Balancers per service

### Feature: API Gateway & VPC Link

**US-007** — As a dev, I want a shared HTTP API connected to a single ALB inside the VPC
- [ ] T-031 (D11) aws_apigatewayv2_api resource (HTTP API)
- [ ] T-032 (D11) aws_apigatewayv2_vpc_link pointing to **1 shared ALB** (not 1 per service)
- [ ] T-033 (D12) Default stage + auto-deploy + access logging to CloudWatch
- [ ] T-034 (D12) Document the routing pattern: shared Ingress inside the cluster routes by path to each service (identity-api, future asset-registry-api, etc.)
- [ ] T-035 (D12) ADR-004: no native authorizer on the Gateway — JWT (HS256) validation stays in the service
- [ ] T-059 (D13) ADR-006: 1 shared Ingress/ALB instead of 1 NLB per microservice — cost decision (~$16/month saved per service)
- [ ] T-040 (D13) Integration test via the default API Gateway URL (`*.execute-api.*.amazonaws.com`) — no custom domain for now

> **Backlog / Phase 2:** WAF (managed rule groups + rate limit), ACM certificate and custom domain on Route53 — defer until there's real production traffic or the domain is purchased. Use the default API Gateway URL until then (free, already comes with HTTPS).

---

## Epic 5 — Shared Identity & Secrets
**Days 14–15**
🎯 Shared Cognito User Pool — already essentially free at this project's volume

### Feature: Cognito & Shared Configuration

**US-009** — As a dev, I want a shared Cognito User Pool for social login and MFA across all services
- [ ] T-041 (D14) aws_cognito_user_pool (password policy, MFA config)
- [ ] T-042 (D14) Cognito hosted domain (hosted UI)
- [ ] T-043 (D15) Google/Apple IdP federation stubs (aligned with identity-api's ADR-006)
- [ ] T-044 (D15) Publish User Pool ID + region to SSM for services to consume

**US-010** — As a security engineer, I want platform-level secrets and keys discoverable through a clear convention
- [ ] T-045 (D15) Shared KMS key (~$1/month) for platform-level encryption needs
- [ ] T-046 (D15) SSM namespace convention: /rentifyx/platform/*
- [ ] T-047 (D15) ADR-005: SSM Parameter Store instead of terraform_remote_state across repos

---

## Epic 6 — Observability (free tier) & Production
**Days 16–17**
🎯 Centralized telemetry with no license cost — CloudWatch free tier instead of Datadog

### Feature: Observability & Hardening

**US-011** — As a dev, I want centralized telemetry without paying for a third-party tool
- [ ] T-048 (D16) OTEL Collector on EKS (helm_release) exporting to CloudWatch
- [ ] T-049 (D16) **CloudWatch Logs/Metrics only** — Datadog agent removed from the MVP (revisit if/when there's an observability budget)
- [ ] T-050 (D16) Short log retention (7–14 days) to reduce storage cost

**US-012** — As a tech lead, I want a final security review and documentation before v1.0.0
- [ ] T-051 (D17) Full checkov/tfsec scan — fix all High/Critical findings
- [ ] T-052 (D17) C4 Context diagram: rentifyx-platform in the RentifyX ecosystem
- [ ] T-053 (D17) Onboarding README: how a new service repo consumes platform outputs
- [ ] T-054 (D17) Finalize ADRs 001–006, cross-link in /docs/adr/
- [ ] T-055 (D17) Tag v1.0.0 → enables rentifyx-identity-api to migrate its Ingress here

---

## Epic 7 — Bootstrap & Teardown Runbook *(new)*
**Day 18**
🎯 Stand everything up, test it, and tear everything down without leaving orphaned resources billing on their own — essential since the environment won't stay up 24/7

### Feature: Full Lifecycle Scripts

**US-013** — As a dev, I want to bring the whole environment up predictably to test quickly
- [ ] T-060 (D18) `bootstrap.sh`: applies modules in the correct order (network → eks → api-gateway → cognito)
- [ ] T-061 (D18) `wait-for-ready.sh`: waits for the cluster/Fargate profile to reach `ACTIVE` before applying K8s manifests (the biggest time sink, ~15–20min)
- [ ] T-062 (D18) Document expected startup time and what to check if it stalls (cluster stuck in `CREATING`, pending Fargate profile)

**US-014** — As a dev, I want to tear everything down without the destroy hanging or leaving an orphaned resource billing on its own
- [ ] T-063 (D18) `teardown.sh` with the exact order:
  ```bash
  # 1. Remove the Ingress first — the ALB is created by the controller, not by Terraform
  kubectl delete ingress --all -n <namespace>

  # 2. Confirm the ALB is actually gone before proceeding
  aws elbv2 describe-load-balancers --region sa-east-1 \
    --query "LoadBalancers[?contains(LoadBalancerName, 'rentifyx')]"
  # (repeat until it comes back empty — usually takes ~60-90s)

  # 3. Only then destroy the Terraform infra, in reverse order of creation
  terraform destroy -target=module.api_gateway
  terraform destroy -target=module.eks
  terraform destroy -target=module.network
  # backend (S3 state bucket + DynamoDB lock) NEVER goes into the destroy
  ```
- [ ] T-064 (D18) Post-destroy verification checklist (via `aws` CLI or console): no orphaned ALB, NAT Gateway, Elastic IP, or ENI left behind
- [ ] T-065 (D18) ADR-007: the state's S3 bucket + DynamoDB table are never destroyed between test cycles — only the infra they describe
- [ ] T-066 (D18) Operational note: `aws_kms_key` doesn't delete instantly — AWS forces ~7 days of "pending deletion." This is expected, not an error; the key stops incurring meaningful cost during that window.

> **Real cost of a test cycle:** EKS + NAT + ALB + VPC Link together run ~$0.25/hour. A 4–6h test costs **$1–2 total** — not the $245-255 monthly figure, which only applies if it stays up the whole month.

---

## Known Decisions & Watch Items

| ID | Decision / Item | Note |
|---|---|---|
| ADR-002 | Single NAT | Saves ~$64/month; accepts downtime if the NAT's AZ goes down. Revisit if/when real traffic requires HA. |
| ADR-003 | Fargate instead of node group | Eliminates idle EC2 cost; accepts higher per-pod cold start and less fine-grained instance control. |
| ADR-004 | No native authorizer on the API Gateway | identity-api's HS256 JWT isn't compatible with the native JWT Authorizer (RS256/JWKS). Validation stays in the service. |
| ADR-005 | SSM Parameter Store as the contract between repos | Avoids granting full state read access from one repo to another. |
| ADR-006 | 1 shared Ingress/ALB | Avoids 1 NLB per microservice; path-based routing inside the cluster. |
| WATCH-01 | identity-api's Ingress migration | Once this repo reaches v1.0.0, migrate the edge configuration here, without duplicating resources. |
| WATCH-02 | EKS control plane is a fixed cost | ~$73/month regardless of usage; the one item that doesn't scale to zero while keeping managed EKS. |
| ADR-007 | State backend is never destroyed | S3 (versioned) + DynamoDB (lock) stay outside the teardown cycle — deleting the bucket that holds the destroy's own state is a chicken-and-egg problem. |
| WATCH-03 | The ALB isn't managed by Terraform | Created by the AWS Load Balancer Controller when the K8s `Ingress` is applied. If destroy doesn't remove the Ingress first, the ALB is left orphaned billing (~$25-30/month) without showing up in the state. |

## Gap Analysis

| Gap | Impact | Status |
|---|---|---|
| A staging environment literally doubled every fixed cost | Resolved — single environment (prod) for now | ✅ Resolved |
| 3 NAT Gateways (1 per AZ) | Resolved — 1 shared NAT, ~$64/month saved | ✅ Resolved |
| 1 NLB per microservice would multiply cost with every new service | Resolved — 1 shared Ingress/ALB (ADR-006) | ✅ Resolved |
| Datadog agent required a paid license with no real need yet | Resolved — CloudWatch free tier in the MVP | ✅ Resolved |
| No budget alert existed in the original plan | Resolved — AWS Budgets + SNS (T-056–058) | ✅ Resolved |
| WAF and custom domain added cost before there was real traffic | Deferred to Phase 2 — use the default API Gateway URL for now | ⚠️ Open (intentional) |
| Fargate profile sizing depends on how many services will run concurrently | Revisit sizing when adding asset-registry-api | ⚠️ Open |
| No teardown runbook existed — real risk of an orphaned ALB billing on its own | Resolved — `teardown.sh` with explicit ordering (T-060–066) and post-destroy verification | ✅ Resolved |
