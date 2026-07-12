# Rentifyx Platform

`rentifyx-platform` is the shared AWS infrastructure repository for the RentifyX ecosystem. Its goal is to provide a reusable, low-cost platform foundation that other RentifyX services can build on.

## What this repository is for

This repo defines the platform-level infrastructure that should be shared across services, including:

- Terraform remote state backend and safe environment setup
- VPC with a shared NAT Gateway and private subnets
- EKS cluster running on Fargate to avoid idle EC2 costs
- Shared HTTP entry point via API Gateway + VPC Link + ALB
- Cognito User Pool for centralized identity management
- Observability skeleton using OpenTelemetry and CloudWatch
- GitHub Actions validation for Terraform, tflint, and Checkov

## Why it exists

The intention is to minimize ongoing AWS costs while still using managed services. This repository targets a single production environment and defers expensive or complex items until a later phase.

Key cost-focused decisions:

- Single environment only (`prod`)
- One shared NAT Gateway instead of one per AZ
- EKS on Fargate rather than EC2 node groups
- Shared ALB/Ingress instead of one per microservice
- CloudWatch free-tier observability instead of a paid service

## Repository structure

- `modules/` — Terraform module skeletons:
  - `network/`
  - `eks/`
  - `api-gateway/`
  - `cognito/`
  - `observability/`
- `prod/` — environment-specific Terraform entrypoint
- `scripts/` — support scripts for bootstrap and teardown
- `docs/adr/` — architectural decision records
- `.specs/project/` — project vision, roadmap, and state tracking
- `.github/` — GitHub Actions workflow and PR template

## Current status

This repository currently contains scaffolding and configuration templates. Most modules are skeletons and must be completed before provisioning any AWS infrastructure.

## Getting started

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and update values.
2. Review `backend.tf` and configure the S3/DynamoDB backend for remote state.
3. Complete the Terraform module implementations in `modules/`.
4. Validate the repository with:
   - `terraform fmt -check`
   - `terraform init`
   - `terraform validate`
5. Use `.github/workflows/terraform.yml` for CI validation on pull requests.

## Recommended workflow

- Keep `prod/` as the single environment entrypoint.
- Do not create a staging environment yet.
- Do not provision resources until all module logic is implemented.
- Use PR reviews to verify Terraform changes and cost guardrails.

## Notes

- `pull_request.md` is a repository helper, but GitHub uses `.github/PULL_REQUEST_TEMPLATE.md` automatically.
- The current state is intentionally conservative: only scaffolding and governance should exist now.
- The repository should be updated as each platform module is implemented, not by provisioning incomplete infrastructure.
