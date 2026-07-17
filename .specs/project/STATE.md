# Project State

## Last Updated

2026-07-17

## Decisions

- `prod` is the only initial environment.
- Remote state infrastructure uses S3 + DynamoDB and is not destroyed during the teardown cycle. Real bucket/table (verified against AWS 2026-07-17): `rentifyx-tfstate-166613156216` / `rentifyx-tflock`, account `166613156216`, region `us-east-1` — this is the account the project is standardizing on (a separate account, `480831398199`, was decommissioned 2026-07-17: its `terraform-user` IAM user's access keys and group membership were deleted).
- The project prioritizes cost reduction over full high availability.
- **ADR-002 (2026-07-17): EKS removed entirely, Kafka runs on MSK Serverless.** Supersedes ADR-001 (self-hosted Kafka on a dedicated EC2 node group inside EKS). Nothing in this platform needs a Kubernetes cluster: `rentifyx-identity-api` deploys via its own EC2 module, `rentifyx-communications-api` has no IaC of its own yet, and Kafka (the only reason EKS existed) now runs as `aws_msk_serverless_cluster` with SASL/IAM client auth. See `docs/adr/002-msk-serverless.md`.

## Blockers

_None active._ `terraform validate`/`plan` both succeed end-to-end (33 resources, 0 errors) — `terraform apply` has still never been attempted for the bulk of this repo's resources (network/kafka/api-gateway/cognito/observability), by deliberate choice (real VPC/NAT/MSK cost), not because anything is broken.

## Resolved (2026-07-17 session)

- ~~`backend.tf` used `var.state_bucket`/`var.aws_region`/`var.dynamodb_table` inside the `backend "s3" {}` block~~ — Terraform disallows variable references there (must resolve before any variables are read), so `terraform init` had never actually worked from a clean checkout. Fixed with literal values (see Decisions above for the real bucket/table/account, discovered via direct AWS API calls after two wrong-account/wrong-bucket-name detours - the account confusion was caused by a stale `AWS_ACCESS_KEY_ID` env var silently overriding `--profile rentifyx-admin`).
- ~~`.github/workflows/terraform.yml` pinned `terraform_version: 1.5.8`~~, which no longer resolves via `hashicorp/setup-terraform`'s version lookup — bumped to `1.7.4` (versions.tf only requires `>= 1.5`).
- ~~No AWS credentials configured in `terraform.yml`~~ — added `modules/github-actions-oidc` (IAM OIDC role scoped to this repo's CI, S3/DynamoDB backend access only - not infra-creation permissions) and wired `aws-actions/configure-aws-credentials` into the workflow. Applied for real 2026-07-17: `RentifyX-prod-github-ci` role + the shared `token.actions.githubusercontent.com` OIDC provider now exist in AWS. `AWS_DEPLOY_ROLE_ARN` GitHub secret set by the user.
- ~~`tflint --module` flag~~ — removed in tflint 0.54+, now `--call-module-type=all`.
- ~~11 checkov findings across eks/network/observability/kafka modules~~ — 10 fixed for real (EKS control-plane logging/secrets-encryption/restricted-public-endpoint - since removed with EKS itself; VPC flow logs, default security group locked down, public subnets no longer auto-assign IPs; CloudWatch log groups KMS-encrypted + 1yr retention; Kafka SSM parameter encrypted). 1 (`CKV_AWS_39`, "EKS public endpoint disabled") was a deliberate accepted trade-off, not silently suppressed - moot now that EKS is gone. 9 more findings introduced by the KMS-key-policy fixes themselves (`CKV_AWS_109/111/356` on the mandatory root-admin grant every KMS key needs) are `#checkov:skip`'d inline with justification - confirmed via research this is AWS's own default-generated key policy pattern, not a real over-permission.
- ~~EKS + Strimzi-on-EC2-node-group Kafka setup~~ — replaced with MSK Serverless per ADR-002. `modules/eks/` deleted entirely; `modules/kafka/` rewritten (SASL/IAM auth, own security group, no Helm/node-group/EBS-storage-class). Root `outputs.tf` added, exposing `kafka_client_iam_policy_json`/`kafka_cluster_arn`/`kafka_ssm_parameter_path` for `rentifyx-identity-api`/`rentifyx-communications-api` to consume via `terraform_remote_state`.

## Applied to real AWS (2026-07-17)

Only `module.github_actions_oidc` (3 resources: OIDC provider, `RentifyX-prod-github-ci` IAM role, its backend-scoped policy) — everything else (network/kafka/api-gateway/cognito/observability) is validated/planned but **not applied**. No VPC, EC2, or MSK cluster exists yet. Verified directly against AWS 2026-07-17: `aws iam list-roles`/`list-open-id-connect-providers`, `aws ec2 describe-vpcs`/`describe-instances`, `aws kafka list-clusters-v2` all confirm nothing else exists.

## Pending

- Real `terraform apply` of `module.network`/`module.kafka` (and the rest) - deliberately deferred, real cost (NAT Gateway ~$32/mo, MSK Serverless usage-based). Requires staged apply (`-target=module.network -target=module.kafka` first - `module.kafka`'s... actually no Kubernetes chicken-egg anymore post-MSK migration, but network must still exist before kafka for `vpc_id`/`private_subnets`).
- `eks_public_access_cidrs`-equivalent concern is now moot (no EKS) - no outstanding placeholder-CIDR follow-up.
- `rentifyx-identity-api`/`rentifyx-communications-api` both need SASL/IAM (AWS SigV4 OAUTHBEARER) wiring in their Confluent.Kafka clients before either can actually talk to MSK Serverless in production - the IAM policy attachment is done (code-side, `count=0`/`try()` no-op until this repo's Kafka is applied), the client auth code is not.
