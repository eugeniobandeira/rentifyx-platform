# Project State

## Decisions

- `prod` is the only initial environment.
- Remote state infrastructure uses S3 + DynamoDB and is not destroyed during the teardown cycle.
- The project prioritizes cost reduction over full high availability.

## Blockers

- **`prod/main.tf` is disconnected from the repo root.** Discovered 2026-07-15 while wiring `modules/kafka/`: `terraform init`/`validate` run at the repo root never sees `prod/main.tf` (Terraform doesn't descend into subdirectories on its own), and `prod/` has no `providers.tf`/`backend.tf`/`versions.tf` of its own — so nothing in `prod/main.tf` (all 6 modules: network/eks/kafka/api-gateway/cognito/observability) is actually applicable today. Pre-existing, not introduced by the Kafka feature — affects all modules equally. Needs a structural fix (move `prod/main.tf`'s content into a root-level `main.tf`, or make `prod/` its own root module with its own copy of provider/backend config) before any real `terraform apply` will work.

## Pending

- Create `backend.tf` and configure the remote backend.
- Define Terraform modules under `modules/`.
- Implement bootstrap and teardown scripts.
- Configure GitHub Actions to validate Terraform.
