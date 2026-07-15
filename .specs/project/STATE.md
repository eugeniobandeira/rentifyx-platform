# Project State

## Decisions

- `prod` is the only initial environment.
- Remote state infrastructure uses S3 + DynamoDB and is not destroyed during the teardown cycle.
- The project prioritizes cost reduction over full high availability.

## Blockers

- **`modules/network`'s `private_subnets` output is hardcoded to `[]`.** Discovered 2026-07-15 while fixing the `prod/main.tf` wiring gap (below) — once `terraform validate` actually ran end to end for the first time, this became visible as the next real gap: `modules/network` only creates a bare `aws_vpc` (no subnets, no NAT, no route tables), so every module that consumes `private_subnets` (`eks`, `kafka`, `api_gateway`) receives an empty list. `terraform validate` doesn't catch this (it's a valid empty list, not a type error) but `terraform plan`/`apply` will fail once EKS actually tries to place a cluster/node group into zero subnets. Needs real subnet + NAT Gateway + route table resources in `modules/network` before any `apply` can succeed.

## Resolved

- ~~`prod/main.tf` is disconnected from the repo root~~ — fixed 2026-07-15: moved composition into a root-level `main.tf` (module sources `./modules/*`), matching what `scripts/bootstrap.sh` already documented ("run terraform init in the root directory"). `prod/main.tf` removed. While fixing this, `terraform validate` ran successfully end-to-end for the first time ever in this repo, surfacing two more pre-existing bugs, also fixed same day: (1) all 5 pre-Kafka modules had a duplicate `output` block (once inline in `main.tf`, once in `outputs.tf`) — removed the inline duplicates; (2) `modules/eks` required a `cluster_role_arn` input that nothing ever created or passed — the module was unusable standalone. It now creates its own IAM role (`AmazonEKSClusterPolicy`), the same pattern `modules/kafka` already uses for its node role.

## Pending

- Create `backend.tf` and configure the remote backend.
- Define Terraform modules under `modules/`.
- Implement bootstrap and teardown scripts.
- Configure GitHub Actions to validate Terraform.
