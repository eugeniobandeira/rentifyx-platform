# Project State

## Decisions

- `prod` is the only initial environment.
- Remote state infrastructure uses S3 + DynamoDB and is not destroyed during the teardown cycle.
- The project prioritizes cost reduction over full high availability.

## Blockers

_None active._ `modules/network`'s `private_subnets` gap (below, Resolved) was the last known
blocker to a real `terraform apply` — not yet attempted against real AWS, but nothing known is
structurally broken anymore.

## Resolved

- ~~`prod/main.tf` is disconnected from the repo root~~ — fixed 2026-07-15: moved composition into a root-level `main.tf` (module sources `./modules/*`), matching what `scripts/bootstrap.sh` already documented ("run terraform init in the root directory"). `prod/main.tf` removed. While fixing this, `terraform validate` ran successfully end-to-end for the first time ever in this repo, surfacing two more pre-existing bugs, also fixed same day: (1) all 5 pre-Kafka modules had a duplicate `output` block (once inline in `main.tf`, once in `outputs.tf`) — removed the inline duplicates; (2) `modules/eks` required a `cluster_role_arn` input that nothing ever created or passed — the module was unusable standalone. It now creates its own IAM role (`AmazonEKSClusterPolicy`), the same pattern `modules/kafka` already uses for its node role.
- ~~`modules/network`'s `private_subnets` output is hardcoded to `[]`~~ — fixed 2026-07-15: `modules/network` now provisions 2 public + 2 private subnets across 2 AZs, an Internet Gateway, one shared NAT Gateway (deliberate single-NAT cost trade-off per `PROJECT.md` Constraints — not one per AZ), and route tables. `private_subnets`/new `public_subnets` outputs return real subnet IDs. Unblocks `eks`, `kafka`, and `api_gateway`, all of which consume `private_subnets`.

## Pending

- Create `backend.tf` and configure the remote backend.
- Define Terraform modules under `modules/`.
- Implement bootstrap and teardown scripts.
- Configure GitHub Actions to validate Terraform.
