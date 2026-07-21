# Self-Hosted Kafka (replace AWS MSK Serverless) Tasks

**Design**: `.specs/features/self-hosted-kafka/design.md`
**Status**: Done (T1-T13 complete 2026-07-21; not yet applied against real AWS or PR'd)

---

## Execution Plan

**Phase 1 (T1-T5): DONE** — commit `313cbea` on branch `feat/self-hosted-kafka`. `terraform validate` passed; `terraform plan -target=module.kafka` confirmed 11 resources to create (network + kafka broker EC2/SG/IAM/SSM), 0 destroy, 0 unexpected changes.

### Phase 1: Platform infra (mostly sequential — same module's files)

```
T1 → T2 → T3
       ↘  ↙
        T4 [P with T3, not with T1/T2]
         ↓
        T5
```

### Phase 2: identity-api (parallel with Phase 3)

```
T6 → T7
T6 ──→ T8 [P with T7]
```

### Phase 3: comms-api (parallel with Phase 2)

```
T9  ─┐
T10 ─┴→ T11
T9  ──→ T12 [P with T11]
T10 ──→ T12 [P with T11]
```

### Phase 4: Docs sync (sequential, after everything above)

```
T5, T7, T8, T11, T12 → T13
```

---

## Task Breakdown

### T1: Rewrite `modules/kafka`'s core resources (EC2, security group, IAM role)

**What**: In `rentifyx-platform/modules/kafka/main.tf`, remove `aws_msk_serverless_cluster.this`, `aws_security_group.msk` + its 3 ingress/egress rules, and `data.aws_iam_policy_document.kafka_client`. Add `aws_security_group.kafka` (ingress `9092/tcp` from `var.vpc_cidr`, egress all), `data.aws_ami.amazon_linux_2023` + `aws_instance.kafka` (`t3.micro`, `lifecycle { ignore_changes = [ami] }`), `aws_iam_role.kafka` + `AmazonSSMManagedInstanceCore` attachment + `aws_iam_instance_profile.kafka`. Update `variables.tf` (drop anything MSK-specific, no new vars needed beyond what already exists: `vpc_id`, `private_subnets`).
**Where**: `rentifyx-platform/modules/kafka/main.tf`, `rentifyx-platform/modules/kafka/variables.tf`
**Depends on**: None
**Reuses**: `rentifyx-identity-api/iac/terraform/modules/ec2/main.tf`'s AMI-lookup + IAM role + security group shape (per design.md Code Reuse Analysis)
**Requirement**: KAFKA-01, KAFKA-04

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `aws_msk_serverless_cluster.this` and all MSK-only resources/data sources removed
- [ ] `aws_instance.kafka` defined with `lifecycle.ignore_changes = [ami]`
- [ ] `aws_security_group.kafka` allows `9092/tcp` ingress from `var.vpc_cidr` only
- [ ] `terraform fmt -check` passes
- [ ] `terraform validate` passes (no template file yet, so `user_data` block will fail until T2 — acceptable, validated fully in T5)

**Tests**: none (Terraform infra, no app-level test type applies)
**Gate**: `terraform fmt -check` (this task only; full `terraform validate` deferred to T5)

---

### T2: Write `modules/kafka/userdata.sh.tpl`

**What**: Cloud-init script installing Docker and starting `apache/kafka` in KRaft combined mode, templated with the instance's own private IP for `KAFKA_ADVERTISED_LISTENERS`.
**Where**: `rentifyx-platform/modules/kafka/userdata.sh.tpl` (new file)
**Depends on**: T1 (needs `aws_instance.kafka` to reference `self.private_ip` via `templatefile()`)
**Reuses**: identity-api's `modules/ec2/main.tf` `templatefile()` invocation pattern
**Requirement**: KAFKA-01, KAFKA-02

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] Script installs Docker (`dnf install docker` or `amazon-linux-extras`, matching identity-api's own userdata pattern) and starts it
- [ ] Script resolves its own private IP at boot time via the EC2 instance metadata endpoint (`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`) into a shell variable — **not** a Terraform-templated value, since `aws_instance.kafka.private_ip` isn't known until after the instance (and its `user_data`) is created, so a `templatefile()` self-reference isn't possible here
- [ ] Runs `apache/kafka` container with `KAFKA_PROCESS_ROLES=broker,controller`, `KAFKA_NODE_ID=1`, `KAFKA_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093`, `KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093`, `KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://$LOCAL_IP:9092` (using the shell variable from the step above), `KAFKA_AUTO_CREATE_TOPICS_ENABLE=true`
- [ ] `aws_instance.kafka`'s `user_data` in `main.tf` wired to `templatefile("${path.module}/userdata.sh.tpl", {})` (no `private_ip` var needed — this file only needs Terraform-templated values if/when a future var is added; today it needs none)

**Tests**: none
**Gate**: shell syntax check (`bash -n userdata.sh.tpl` after stripping any `${...}` template markers, or visual review — no CI step exists for this file type)

---

### T3: Update `modules/kafka/ssm.tf`

**What**: Change `aws_ssm_parameter.kafka_bootstrap_servers`'s `value` from `aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam` to `"${aws_instance.kafka.private_ip}:9092"`.
**Where**: `rentifyx-platform/modules/kafka/ssm.tf`
**Depends on**: T1 (needs `aws_instance.kafka` to exist)
**Reuses**: Same resource, same name/path/type — see design.md Code Reuse Analysis
**Requirement**: KAFKA-03

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `value` sourced from the new EC2 instance's private IP + `:9092`
- [ ] Parameter name/path/`SecureString` type unchanged
- [ ] `terraform fmt -check` passes

**Tests**: none
**Gate**: `terraform fmt -check`

---

### T4: Update `modules/kafka`'s outputs, `docs/kafka-ui.md`, `scripts/start-kafka-ui.sh` [P]

**What**: Remove `client_iam_policy_json` output from `modules/kafka/outputs.tf` (and `bootstrap_servers`/`cluster_arn` outputs that referenced the MSK resource — replace with equivalents pointing at `aws_instance.kafka` where still meaningful, or drop if nothing consumes them). Update `scripts/start-kafka-ui.sh` to drop the `IAMLoginModule required;` SASL config and connect with a plain `bootstrap.servers` pointing at the new broker. Update `docs/kafka-ui.md`'s runbook text to match.
**Where**: `rentifyx-platform/modules/kafka/outputs.tf`, `rentifyx-platform/scripts/start-kafka-ui.sh`, `rentifyx-platform/docs/kafka-ui.md`
**Depends on**: T1, T3 (needs to know the new SSM parameter shape / instance IP source)
**Reuses**: Existing `start-kafka-ui.sh`/`kafka-ui.md` structure from the `kafka-ui-access` feature — only the auth block changes
**Requirement**: KAFKA-08

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `client_iam_policy_json` output removed from `outputs.tf`
- [ ] `start-kafka-ui.sh` resolves the SSM parameter (now `host:port`) and sets kafbat-ui's `KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL=PLAINTEXT` (or omits security config entirely, whichever kafbat-ui's compose/env convention expects) — no `IAMLoginModule`
- [ ] `docs/kafka-ui.md` text updated to describe the new (no-IAM) connection step

**Tests**: none
**Gate**: manual review (shell script, no CI for this file type)

---

### T5: Full `terraform validate`/`plan` gate for `rentifyx-platform`

**What**: Run `terraform validate` and `terraform plan` against the rewritten `modules/kafka` (and root `main.tf`, unchanged but re-verified) to confirm the module is internally consistent end-to-end.
**Where**: `rentifyx-platform/` (root)
**Depends on**: T1, T2, T3, T4
**Reuses**: N/A — verification task
**Requirement**: KAFKA-01, KAFKA-02, KAFKA-03, KAFKA-04

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `terraform init` succeeds
- [ ] `terraform validate` passes with zero errors
- [ ] `terraform plan` shows the expected diff (destroy MSK resources, create EC2/SG/IAM role/instance profile) with no unexpected changes elsewhere in the plan

**Tests**: none
**Gate**: `terraform validate && terraform plan`

**Commit**: `feat(kafka): replace MSK Serverless with self-hosted KRaft broker on EC2`

---

### T6: Simplify `rentifyx-identity-api`'s `KafkaProducerFactory` [P]

**What**: Remove the `IHostEnvironment`-gated SASL/IAM branch entirely — `Create()` always builds `new ProducerConfig { BootstrapServers = bootstrapServers }` with no `SecurityProtocol`/`SaslMechanism`. Remove the `IHostEnvironment environment` constructor parameter, `AWSMSKAuthTokenGenerator` field, `using AWS.MSK.Auth;`/`using Amazon;` directives. Update `KafkaProducerFactoryTests.cs` to drop the 2 production-branch tests (`Create_WhenProductionWithoutAwsRegionConfigured_Throws`, `Create_WhenProductionWithAwsRegionConfigured_ReturnsSaslIamProducer`) and the `Mock<IHostEnvironment>` setup from the remaining 2 tests.
**Where**: `RentifyxIdentity.Infrastructure/Messaging/KafkaProducerFactory.cs`, `03-tests/03-Handlers/RentifyxIdentity.Tests.Handlers/Messaging/KafkaProducerFactoryTests.cs`
**Depends on**: None
**Reuses**: N/A — simplification of existing code
**Requirement**: KAFKA-05, KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `IHostEnvironment` no longer a constructor dependency
- [ ] No `SecurityProtocol`/`SaslMechanism`/`AWSMSKAuthTokenGenerator` references remain in the file
- [ ] `KafkaProducerFactoryTests.cs` has exactly 2 tests: throws with no bootstrap servers, returns a producer when configured
- [ ] Gate check passes: `dotnet test 03-tests/03-Handlers`
- [ ] Test count: 2 tests pass in this class (down from 4 — not a silent deletion, both removed tests asserted SASL/IAM behavior that no longer exists)

**Tests**: unit (Handlers, per TESTING.md matrix)
**Gate**: quick

---

### T7: Remove `AWS.MSK.Auth` package reference (identity-api)

**What**: Remove the `AWS.MSK.Auth` package from `Directory.Packages.props` and the one `.csproj` that referenced it (`RentifyxIdentity.Infrastructure`).
**Where**: `Directory.Packages.props`, `02-src/05-Infrastructure/RentifyxIdentity.Infrastructure/RentifyxIdentity.Infrastructure.csproj`
**Depends on**: T6 (code must stop referencing the package first)
**Reuses**: N/A
**Requirement**: KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `AWS.MSK.Auth` absent from both files
- [ ] `dotnet build RentifyxIdentity.slnx -c Release` succeeds with zero errors

**Tests**: none (package removal, no new behavior)
**Gate**: build

---

### T8: Stop wiring `kafka_client_policy_json` into identity-api's `module.ec2` [P]

**What**: Remove the `kafka_client_policy_json = ...` argument from root `main.tf`'s `module "ec2"` call (the variable itself can stay with its existing `default = ""` — no consumer needs a value anymore, and the `count`-gated `aws_iam_role_policy.ec2_kafka` resource already no-ops on empty string).
**Where**: `rentifyx-identity-api/iac/terraform/main.tf`
**Depends on**: T6 (logically independent of code, but grouped in the same phase to land together)
**Reuses**: Existing `count`-gate no-op behavior already in `modules/ec2/main.tf`
**Requirement**: KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `module "ec2"` call in root `main.tf` no longer passes `kafka_client_policy_json`
- [ ] `terraform validate` passes

**Tests**: none
**Gate**: `terraform validate`

---

### T9: Simplify `rentifyx-communications-api`'s `KafkaConsumerFactory` [P]

**What**: Same simplification as T6, applied to `KafkaConsumerFactory.Create(string groupIdSuffix)`. Update `KafkaConsumerFactoryTests.cs` identically (drop the 2 production-branch tests, drop `Mock<IHostEnvironment>` setup from the rest).
**Where**: `RentifyxCommunications.Api/Messaging/KafkaConsumerFactory.cs`, `03-tests/06-Api/RentifyxCommunications.Tests.Api/Messaging/KafkaConsumerFactoryTests.cs`
**Depends on**: None
**Reuses**: N/A — simplification of existing code
**Requirement**: KAFKA-05, KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `IHostEnvironment` no longer a constructor dependency
- [ ] No `SecurityProtocol`/`SaslMechanism`/`AWSMSKAuthTokenGenerator` references remain in the file
- [ ] `KafkaConsumerFactoryTests.cs` has exactly 2 tests
- [ ] Gate check passes: `dotnet test 03-tests/06-Api/RentifyxCommunications.Tests.Api`
- [ ] Test count: 2 tests pass in this class (down from 4, same rationale as T6)

**Tests**: unit
**Gate**: quick

---

### T10: Simplify `rentifyx-communications-api`'s Infrastructure `KafkaProducerFactory` [P]

**What**: Same simplification as T6, applied to `RentifyxCommunications.Infrastructure/Messaging/KafkaProducerFactory.cs` (used by `KafkaFailureRouter`). Update its `KafkaProducerFactoryTests.cs` (in `03-tests/04-Repositories`) identically.
**Where**: `RentifyxCommunications.Infrastructure/Messaging/KafkaProducerFactory.cs`, `03-tests/04-Repositories/RentifyxCommunications.Tests.Repositories/Features/Notifications/KafkaProducerFactoryTests.cs`
**Depends on**: None
**Reuses**: N/A — simplification of existing code
**Requirement**: KAFKA-05, KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `IHostEnvironment` no longer a constructor dependency
- [ ] No `SecurityProtocol`/`SaslMechanism`/`AWSMSKAuthTokenGenerator` references remain in the file
- [ ] `KafkaProducerFactoryTests.cs` has exactly 2 tests
- [ ] Gate check passes: `dotnet test 03-tests/04-Repositories`
- [ ] Test count: 2 tests pass in this class (down from 4, same rationale as T6)
- [ ] `KafkaFailureRouterTests.cs` (same folder, consumes this factory indirectly via DI/mocks) still passes unchanged

**Tests**: unit (this project is named `Tests.Repositories` but this specific test class is a plain unit test with Moq, no Testcontainers — matches the existing file's own pattern, not a new gap)
**Gate**: quick

---

### T11: Remove `AWS.MSK.Auth` package reference (comms-api)

**What**: Remove the `AWS.MSK.Auth` package from `Directory.Packages.props` and both referencing `.csproj` files (`RentifyxCommunications.Api`, `RentifyxCommunications.Infrastructure`).
**Where**: `Directory.Packages.props`, `02-src/01-Api/RentifyxCommunications.Api/RentifyxCommunications.Api.csproj`, `02-src/05-Infrastructure/RentifyxCommunications.Infrastructure/RentifyxCommunications.Infrastructure.csproj`
**Depends on**: T9, T10 (code must stop referencing the package first)
**Reuses**: N/A
**Requirement**: KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `AWS.MSK.Auth` absent from all three files
- [ ] `dotnet build RentifyxCommunications.slnx -c Release` succeeds with zero errors

**Tests**: none (package removal, no new behavior)
**Gate**: build

---

### T12: Stop wiring `kafka_client_policy_json` into comms-api's `module.ec2` [P]

**What**: Same as T8, applied to `rentifyx-communications-api`'s root `main.tf`.
**Where**: `rentifyx-communications-api/iac/terraform/main.tf`
**Depends on**: T9, T10 (grouped in the same phase to land together)
**Reuses**: Existing `count`-gate no-op behavior already in `modules/ec2/main.tf`
**Requirement**: KAFKA-06

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] `module "ec2"` call in root `main.tf` no longer passes `kafka_client_policy_json`
- [ ] `terraform validate` passes

**Tests**: none
**Gate**: `terraform validate`

---

### T13: Sync STATE.md across all 3 repos

**What**: Document the migration (MSK Serverless → self-hosted KRaft broker) in `.specs/project/STATE.md` in all three repos, including the accepted trade-offs (single broker, no persistence, PLAINTEXT) and the new component ownership (`rentifyx-platform` owns the broker EC2, matching `module.network`/`module.kafka`'s existing precedent).
**Where**: `rentifyx-platform/.specs/project/STATE.md`, `rentifyx-identity-api/.specs/project/STATE.md`, `rentifyx-communications-api/.specs/project/STATE.md`
**Depends on**: T5, T7, T8, T11, T12
**Reuses**: N/A
**Requirement**: N/A (housekeeping, not user-facing)

**Tools**: MCP: NONE / Skill: NONE

**Done when**:

- [ ] All three STATE.md files mention the migration, its date, and cross-link to `rentifyx-platform`'s `.specs/features/self-hosted-kafka/`
- [ ] No stale references to `AWS.MSK.Auth`/SASL-IAM remain describing *current* behavior anywhere in the three repos' living docs (README, CLAUDE.md, `.specs/codebase/*`) — historical feature specs/tasks stay untouched as frozen records, same convention already established this session

**Tests**: none
**Gate**: none (docs-only)

**Commit**: `docs: record self-hosted Kafka migration in STATE.md`

---

## Parallel Execution Map

```
Phase 1 (platform, sequential T1→T2→T3, T4 parallel-ready once T3 done):
  T1 ──→ T2 ──→ T3 ──→ T4 ──→ T5

Phase 2 (identity-api) / Phase 3 (comms-api) — run concurrently with each other, both independent of Phase 1's completion:
  T6 ──→ T7
  T6 ──→ T8 [P with T7]

  T9  ─┐
  T10 ─┴→ T11
  T9  ──→ T12 [P with T11]
  T10 ──→ T12 [P with T11]

Phase 4 (sequential, after T5 + T7 + T8 + T11 + T12):
  T13
```

---

## Task Granularity Check

| Task | Scope | Status |
| --- | --- | --- |
| T1: EC2/SG/IAM role in modules/kafka | 1 module, cohesive infra resources | ✅ Granular |
| T2: userdata.sh.tpl | 1 file | ✅ Granular |
| T3: ssm.tf value change | 1 file, 1 line | ✅ Granular |
| T4: outputs + kafka-ui docs/script | 3 files, same concern (drop IAM auth) | ✅ Granular (cohesive) |
| T5: validate/plan gate | 1 verification step | ✅ Granular |
| T6: identity-api producer factory + its test | 2 files, 1 concept | ✅ Granular |
| T7: package removal (identity-api) | 2 files, 1 concept | ✅ Granular |
| T8: main.tf wiring removal (identity-api) | 1 file | ✅ Granular |
| T9: comms-api consumer factory + its test | 2 files, 1 concept | ✅ Granular |
| T10: comms-api Infrastructure producer factory + its test | 2 files, 1 concept | ✅ Granular |
| T11: package removal (comms-api) | 3 files, 1 concept | ✅ Granular |
| T12: main.tf wiring removal (comms-api) | 1 file | ✅ Granular |
| T13: STATE.md sync | 3 files, 1 concept | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| --- | --- | --- | --- |
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T1 | T2 → T3 (chained via T1→T2→T3) | ✅ Match |
| T4 | T1, T3 | T3 → T4 | ✅ Match |
| T5 | T1, T2, T3, T4 | T4 → T5 | ✅ Match |
| T6 | None | Phase 2 start | ✅ Match |
| T7 | T6 | T6 → T7 | ✅ Match |
| T8 | T6 | T6 → T8 [P with T7] | ✅ Match |
| T9 | None | Phase 3 start | ✅ Match |
| T10 | None | Phase 3 start | ✅ Match |
| T11 | T9, T10 | T9,T10 → T11 | ✅ Match |
| T12 | T9, T10 | T9,T10 → T12 [P with T11] | ✅ Match |
| T13 | T5, T7, T8, T11, T12 | Phase 4 | ✅ Match |

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| --- | --- | --- | --- | --- |
| T1 | Terraform infra (platform, no matrix — infra-only repo) | none | none | ✅ OK |
| T2 | Terraform infra (platform) | none | none | ✅ OK |
| T3 | Terraform infra (platform) | none | none | ✅ OK |
| T4 | Terraform infra + shell script (platform) | none | none | ✅ OK |
| T5 | N/A (verification task) | none | none | ✅ OK |
| T6 | Infrastructure/Messaging (identity-api) — tested from `Tests.Handlers` per existing repo convention, matrix's closest entry is "Handlers: Unit (Moq)" | unit | unit | ✅ OK |
| T7 | Package reference removal | none (no behavior change) | none | ✅ OK |
| T8 | Terraform infra (identity-api) | none | none | ✅ OK |
| T9 | Api/Messaging (comms-api) — tested from `Tests.Api`, same unit-with-Moq pattern as the file's existing tests | unit | unit | ✅ OK |
| T10 | Infrastructure/Messaging (comms-api) — tested from `Tests.Repositories` (project name, but this specific test class is plain unit/Moq, matching its pre-existing pattern, not Testcontainers) | unit | unit | ✅ OK |
| T11 | Package reference removal | none (no behavior change) | none | ✅ OK |
| T12 | Terraform infra (comms-api) | none | none | ✅ OK |
| T13 | Docs only | none | none | ✅ OK |

---

## Tools Confirmation Needed

Per the skill's process, before Execute starts: for each task, which tools should be used?

**Available MCPs**: Context7 (library/API docs lookups — not needed here, `apache/kafka` env vars already confirmed via web search in Design), none else relevant to this feature.
**Available Skills**: `tlc-spec-driven` (this workflow itself); no `mermaid-studio`/`codenavi` installed (checked at Design time — none found, so inline mermaid + built-in Grep/Glob were used instead, per SKILL.md's fallback instructions).

Default plan: no external MCP/skill needed per task — all tasks are direct file edits (Terraform, C#, shell, Markdown) plus `terraform`/`dotnet` CLI gate checks. Confirm this is fine, or flag any task where you want a specific tool used.
