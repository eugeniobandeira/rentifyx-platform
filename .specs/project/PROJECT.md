# RentifyX Platform

## Vision

Build the shared platform infrastructure for the RentifyX ecosystem with minimal cost, using AWS and Terraform, so future services can reuse a secure and maintainable foundation.

## Objective

Provide a single, low-cost AWS environment for the RentifyX platform that includes:

- Shared VPC with public and private subnets
- EKS on Fargate to eliminate idle EC2 instance costs
- HTTP API Gateway with a single shared ALB via VPC Link
- Shared Cognito User Pool for authentication and identity management
- Observability using OTEL Collector and CloudWatch (free tier)
- GitHub Actions for Terraform, tflint, and Checkov validation
- Cost guardrails with AWS Budgets and mandatory cost tags
- Bootstrap and teardown scripts for safe testing without orphaned resources

## Scope

### Included

- Network infrastructure and VPC with one shared NAT Gateway
- Managed EKS cluster using a Fargate profile
- AWS Load Balancer Controller and shared Ingress
- HTTP API Gateway integrated with a shared ALB
- Cognito User Pool and SSM Parameter Store configuration
- Observability with OTEL Collector exporting to CloudWatch
- Terraform remote state using S3 backend and DynamoDB locking
- Infrastructure validation CI/CD

### Excluded (not in first phase)

- Separate staging environment
- Managed WAF and custom domain
- Full VPC Flow Logs
- Datadog or any paid observability tool
- Infrastructure that cannot be destroyed without leaving the state backend intact

## Constraints

- A single environment: `prod`
- One shared NAT Gateway to reduce cost, accepting a single point of failure
- EKS incurs a fixed control plane cost regardless of usage
- The ALB is created by the AWS Load Balancer Controller, so teardown must remove the Ingress first
- The state bucket and DynamoDB lock table are not destroyed as part of teardown

## Definition of Success

- Platform infrastructure successfully created on AWS using Terraform
- Terraform validation and security checks pass on PRs
- Ability to publish useful outputs to other repositories via SSM
- Material monthly cost savings compared to a multi-environment, multi-NAT setup
- Documented and repeatable bootstrap and teardown process
