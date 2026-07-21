# RentifyX Platform

## Vision

Build the shared platform infrastructure for the RentifyX ecosystem with minimal cost, using AWS and Terraform, so `rentifyx-identity-api`/`rentifyx-communications-api` can reuse a secure and maintainable foundation.

## Objective

Provide a single, low-cost AWS environment for the RentifyX platform that includes:

- Shared VPC with public and private subnets
- Self-hosted Kafka (KRaft, single broker, PLAINTEXT) on a dedicated EC2 — replaces the original EKS+Strimzi plan and the later MSK Serverless choice, in that order, both superseded on cost/operational grounds (see `docs/adr/`)
- HTTP API Gateway (provisioned, not yet wired to a backend)
- Shared Cognito User Pool for authentication and identity management
- Shared SES sender identity, consumed cross-repo by both app services
- Observability using a CloudWatch log group for OTel export
- GitHub Actions for Terraform fmt/validate/tflint/checkov
- Bootstrap and teardown scripts for safe testing without orphaned resources

## Scope

### Included

- Network infrastructure and VPC with one shared NAT Gateway
- Self-hosted Kafka broker EC2 (`module.kafka`) — see `.specs/features/self-hosted-kafka/`
- HTTP API Gateway module (exists, not yet integrated with either app service)
- Cognito User Pool and SES shared identity
- CloudWatch log group for OTel export
- Terraform remote state using S3 backend and DynamoDB locking
- Infrastructure validation CI/CD (`terraform.yml`)

### Excluded (not in first phase)

- Separate staging environment
- Managed WAF and custom domain
- A Kubernetes cluster of any kind (EKS was tried and removed 2026-07-17 — nothing in this platform needs it; `rentifyx-identity-api` deploys via its own EC2 module, not EKS pods)
- Datadog or any paid observability tool
- Infrastructure that cannot be destroyed without leaving the state backend intact

## Constraints

- A single environment: `prod`
- One shared NAT Gateway to reduce cost, accepting a single point of failure
- The Kafka broker is a single EC2 instance, no replication — if it dies, Kafka dies with it; accepted trade-off for a study project whose infra is applied/destroyed per test session, not run continuously
- The state bucket and DynamoDB lock table are not destroyed as part of teardown

## Definition of Success

- Platform infrastructure successfully created on AWS using Terraform
- Terraform validation and security checks pass on PRs
- Ability to publish useful outputs to other repositories via SSM/`terraform_remote_state`
- Material monthly cost savings compared to managed alternatives (EKS, MSK Serverless — both tried and rejected on this basis)
- Documented and repeatable bootstrap and teardown process
