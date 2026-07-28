# RentifyX Full-Stack Deploy Runbook

Real errors hit deploying all 5 repos to AWS for the first time in one session (2026-07-27), and
the exact fix for each — so the next full deploy doesn't rediscover any of these the hard way.

## Deploy order (dependency-driven, not arbitrary)

1. **`rentifyx-platform`** — `module.network` + `module.kafka` (VPC/subnets/Kafka broker), then
   `module.ses` separately (shared SES sender identity, consumed by every app repo).
2. **`rentifyx-ai-services`** — owns the asset media S3 bucket. Must go before asset-registry-api
   now (see Bug 3 below).
3. **`rentifyx-identity-api`**
4. **`rentifyx-asset-registry-api`**
5. **`rentifyx-communications-api`**
6. `rentifyx-frontend` — point `environment.ts` at the real EC2 hosts once everything above is up.

Platform's `module.ses` must be applied *before* any app repo's Cognito module — Cognito's own
`SESSourceArn` verification hard-fails if the underlying SES identity doesn't exist yet (Bug 6).

## Environment / tooling gotchas

**Bug 1 — stale AWS credential env vars shadow the profile.** Terraform's provider does its own
`STS GetCallerIdentity` check that fails with `InvalidClientTokenId` even when the bare `aws` CLI
call with the same profile succeeds, if `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/
`AWS_SESSION_TOKEN` are already set in the shell (leftover from an old session/tool). **Fix: prefix
every `terraform`/`aws` command with:**
```
env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN AWS_PROFILE=rentifyx-admin AWS_SDK_LOAD_CONFIG=1
```

**Bug 2 — Git Bash mangles leading-slash CLI arguments into Windows paths.** Any AWS CLI arg
starting with a single `/` (SSM parameter names like `/rentifyx/platform/kafka/bootstrap-servers`)
gets silently rewritten to `C:/Program Files/Git/rentifyx/...` by MSYS2's automatic POSIX-to-Windows
path conversion, producing a confusing `ParameterNotFound` with no hint why. **Fix: prefix the
command with `MSYS_NO_PATHCONV=1`** whenever a CLI argument is a literal path-like string that
should NOT be converted (SSM parameter names, S3 keys with a leading slash, etc.) — this is a Windows/Git-Bash-only issue, doesn't affect Linux/macOS shells.

**Bug 3 — the Kafka SSM parameter and the broker itself live in `sa-east-1`, not `us-east-1`.**
Only the Terraform state backend (`rentifyx-tfstate-166613156216` S3 bucket + `rentifyx-tflock`
DynamoDB table) is in `us-east-1` — everything else (VPC, EC2, SSM parameters, Secrets Manager,
ECR, SES) is in `sa-east-1`. Don't assume one region for the whole stack.

## Terraform / IaC gotchas

**Bug 4 — `rentifyx-asset-registry-api` was never wired into `rentifyx-platform`'s API Gateway.**
The gateway module itself (`asset_registry_api_uri` variable, integration, route, all gated behind
`count`) was correct — but root `main.tf` never actually passed the variable (no
`data.terraform_remote_state.asset_registry_api` existed). The variable silently stayed `""`
forever; the route would never be created even after a real deploy, with **no error at all** —
this is the dangerous kind of gap, since `terraform validate`/`plan` never flags a variable that
was simply never wired. **Lesson: audit that every cross-repo `terraform_remote_state` a service
needs is actually present in the *consuming* module's root config, not just that the *providing*
module's outputs exist.**

**Bug 5 — Dedupe's IAM role was missing `AWSLambdaVPCAccessExecutionRole`.** `CreateFunction`
failed with `does not have permissions to call CreateNetworkInterface on EC2`. Moderation and
Enrichment both had this attachment (learned the hard way in an earlier session); it just never got
copied to Dedupe's role when that role was built. **Lesson: when adding a new VPC-attached Lambda,
diff its IAM module against an existing VPC-attached Lambda's IAM module — don't just copy the
Rekognition/S3/DynamoDB-shaped policy statements and assume VPC access comes for free.**

**Bug 6 — S3 bucket notifications reject two Lambda destinations sharing a prefix/suffix filter.**
`PutBucketNotificationConfiguration` failed: `Configuration is ambiguously defined. Cannot have
overlapping suffixes in two rules if the prefixes are overlapping for the same event type.` A
single S3 `ObjectCreated` filter can only fan out to ONE destination directly — not documented
anywhere obvious, only discovered by trying it. Two real fan-out options exist:
- **SNS** (chosen): S3 → SNS topic → one `aws_sns_topic_subscription` per Lambda. SNS relays the
  *exact same* raw S3 event-notification JSON as a string in `Sns.Message` — a triggered Lambda
  only needs to change its entrypoint type from `S3Event` to `SNSEvent` and
  `JsonSerializer.Deserialize<S3Event>(record.Sns.Message)` the embedded string back into the same
  shape. All existing event-processing code/tests stay untouched.
- **EventBridge** (rejected): needs `eventbridge = true` on the bucket notification plus one
  `aws_cloudwatch_event_rule`/`aws_cloudwatch_event_target` per Lambda. EventBridge's "Object
  Created" `detail` schema is a *different shape* than `S3Event` (one event per invocation, not a
  `Records` array) — would have required rewriting every triggered handler's parsing from scratch
  and invalidating already-shipped tests.
- **Lesson**: when a design fans one S3 bucket out to N Lambdas, decide the fan-out mechanism
  *before* writing the Lambda handlers, or budget for a rewrite of the entrypoint layer either way.

**Bug 7 — two repos each declared their own S3 media bucket for the same physical asset uploads.**
`rentifyx-asset-registry-api` had its own `modules/media-bucket` (reasoning: "the service issuing
presigned URLs should own the bucket"), completely separate from `rentifyx-ai-services`' own bucket
(the one Moderation/Enrichment/Dedupe's S3 trigger actually watches). This was flagged as a known,
unresolved conflict in `rentifyx-asset-registry-api/iac/README.md` since E-06 but never fixed before
this deploy — applying either repo's IaC as originally written would have created two buckets, with
uploads silently never reaching the moderation/dedupe pipeline. **Fixed: the repo that *reacts* to
S3 events owns the bucket resource; the repo that only issues presigned URLs consumes it via
`terraform_remote_state`.** This also flips deploy order — `rentifyx-ai-services` must go before
`rentifyx-asset-registry-api` now. **Lesson: when two repos need "the same physical resource,"
resolve which one owns the Terraform resource explicitly — don't let each repo scaffold its own
copy and defer reconciliation.**

## Runtime / app-config gotchas

**Bug 8 — `terraform apply`'s `user_data` doesn't re-run on an existing EC2 instance.** Cloud-init
only executes `user_data` once, at first boot. Since ECR was empty at the moment these instances
first booted, `docker pull ${ecr_repository_url}:latest` failed and (`set -e`) the whole userdata
script aborted *before* `docker run` — the instance exists and Docker is installed, but no container
is running, and nothing about `terraform apply`'s own output signals this (the instance shows
`running`). **Fix for a first deploy done manually (no CI/CD pipeline wired up yet): after pushing
images to ECR, use SSM `RunShellScript` (`aws ssm send-command`, instance already has the SSM Agent
from userdata) to run the same `docker login`/`pull`/`run` sequence by hand.** Long-term this is
exactly what `module.github-actions`'s CI/CD deploy role is *for* — this manual SSM path is a
one-time bootstrap substitute, not the intended repeat path.

**Bug 9 — real per-repo runtime config key names are NOT consistent with each other.** Easy to
copy-paste a working `docker run` from one repo to the next and get it subtly wrong:

| Repo | Kafka env var | Table env var | Extra |
|---|---|---|---|
| `rentifyx-identity-api` | `ConnectionStrings__kafka` | `AWS__DynamoDB__TableName` | — |
| `rentifyx-asset-registry-api` | `Kafka__BootstrapServers` | `AWS__DynamoDb__TableName` | `AWS__S3__BucketName` |
| `rentifyx-communications-api` | `ConnectionStrings__kafka` | `DynamoDb__NotificationsTableName` | — |

Getting the Kafka key wrong doesn't throw a clean error — the app falls back to whatever its
default/empty connection string resolves to (`localhost:9092`), and the real symptom is
`rdkafka` logging `1/1 brokers are down` forever, not a startup crash. **Lesson: always check each
repo's own `iac/terraform/modules/ec2/userdata.sh.tpl` (or its `ConfigurationKeys.cs`) for the
exact env var names — never assume the previous repo's convention carries over.**

**Bug 10 — the JWT signing secret is a real manual step, not something `terraform apply` fills in.**
`rentifyx-identity-api`'s Secrets Manager entry is deliberately created with `secret_string =
"REPLACE_AT_DEPLOY_TIME"` and `lifecycle.ignore_changes = [secret_string]` so Terraform never
clobbers a real value — but on a *first* deploy there is no real value yet, and the app crashes on
its first request with `System.ArgumentException: No supported key formats were found` (not a
crash-on-boot, so `docker ps` looks fine — only `/health` reveals it). **Fix: generate a real RSA
keypair + HMAC key, `aws secretsmanager put-secret-value` a JSON blob shaped
`{"Jwt:PrivateKeyPem": "...", "Hmac:Key": "..."}`, then restart the container** (Secrets Manager is
only read at process boot, not hot-reloaded).

**Bug 11 — `rentifyx-asset-registry-api` needs `rentifyx-identity-api`'s *public* key, derived from
the private key above, in its own Secrets Manager entry (`{"Jwt:PublicKeyPem": "..."}`)** — same
"real manual step on first deploy" class of gap as Bug 10, easy to miss since the container itself
comes up fine (JWT validation only fails on an actual authenticated request, not at boot).

## Quick pre-flight checklist for next time

- [ ] `rentifyx-platform`'s `module.network`/`module.kafka`/`module.ses` all applied (check
      `terraform state list`, not just "did I run apply once")
- [ ] Each app repo's own Terraform applied with `enable_cognito=false`/`enable_github_actions=false`
      overrides if their prerequisites (SES identity / GitHub OIDC provider) aren't up yet, then
      re-apply with them enabled once those prerequisites land
- [ ] All 3 app repos' Docker images built + pushed to their own ECR repos *before* believing
      `terraform apply`'s "instance running" status means the app is actually serving traffic
- [ ] JWT keypair generated and both Secrets Manager entries (identity-api's private key,
      asset-registry-api's derived public key) populated for real
- [ ] Each container (re)started via SSM with the *correct, repo-specific* env var names (see table
      above) after every image push, since userdata's own pull/run only ever ran once at first boot
- [ ] `curl http://<ec2-host>:8080/health` on all three before considering the deploy done — a
      running container is not the same as a healthy one
