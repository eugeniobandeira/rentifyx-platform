# Shared Kafka Cluster on EKS — Tasks

**Design**: `.specs/features/shared-kafka-eks/design.md`
**Status**: Done — T1-T10 all complete (2026-07-15). Terraform written and validated
(`fmt`/`validate`), not yet applied to real AWS — awaiting user go-ahead. Note: T9's "real
`terraform plan` against AWS creds" done-when criterion was intentionally skipped per user
instruction (no live AWS actions without explicit confirmation) — `terraform validate` only.
A pre-existing, out-of-scope gap was found and logged in `STATE.md` Blockers: `prod/main.tf` is
disconnected from the repo root (no root `main.tf`, no provider/backend config under `prod/`) —
affects all 6 modules, must be fixed before any real `apply` works, including this feature's.

**Test/Gate convention for this repo** (no TESTING.md exists — this is Terraform IaC, not
application code; derived from `.github/workflows/terraform.yml`, the only CI gate that exists):
`Tests: none` for every task (no unit-test framework applies to Terraform), `Gate: build` means
`terraform fmt -check && terraform init && terraform validate && tflint --module && checkov -d .`
must pass — this is a hard requirement on every task, not a suggestion.

**SSM parameter path decided now** (spec.md R-04 flagged this as needing cross-repo coordination
before finalizing — resolved here rather than left open, per Agent's Discretion since no
conflicting convention exists in either consumer repo yet): `/rentifyx/platform/kafka/bootstrap-servers`
(String type, per design.md's "no auth configured" decision). Both `rentifyx-identity-api`'s
`outbox-kafka-notifications` design and `rentifyx-communications-api`'s E-06 F-11 must read this
exact path.

---

## Execution Plan

### Phase 1: Node Group Foundation (Sequential)

```
T1 → T2 → T3
```

### Phase 2: Kafka on the Node Group (Sequential — each depends on the cluster state the previous step creates)

```
T3 → T4 → T5 → T6
           └──→ T7
```

### Phase 3: Integration (T9 sequential after Phase 1+2; T8/T10 parallel with each other and with T9's prerequisites)

```
T6, T7 ──→ T9
T5 ──→ T8 [P]
(design.md, no code dep) ──→ T10 [P]
```

---

## Task Breakdown

### T1: Node group IAM role

**What**: `aws_iam_role` + 3 managed policy attachments (`AmazonEKSWorkerNodePolicy`,
`AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`) for the EKS managed node group's
instance role.
**Where**: `modules/kafka/iam.tf`
**Depends on**: None
**Reuses**: `modules/eks/main.tf`'s existing `var.cluster_role_arn` pattern for how this repo
already threads an IAM role ARN into a module — same shape, new role for a different purpose
(node instance role vs. cluster control-plane role, not interchangeable)
**Requirement**: R-02 (resolution), R-01

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] `aws_iam_role.kafka_node_group` with EC2 service assume-role policy
- [ ] All 3 managed policies attached
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T2: EC2 managed node group for Kafka

**What**: `aws_eks_node_group` — min=1/max=1/desired=1 (single broker, no elasticity needed per
design.md's replication-factor-1 decision), `t4g.small` instance type, EBS gp3 root volume
(default node-group disk, no extra EBS resource needed — the node group's own launch template
disk is what Kafka's persistent volume will live on via `local` storage class or `hostPath`,
confirmed at Helm-values time in T5), tagged so pods can target it via `nodeSelector`.
**Where**: `modules/kafka/main.tf`
**Depends on**: T1
**Reuses**: `module.eks.cluster_name` (existing output), `module.network.private_subnets`
(existing output — currently an empty list per prior exploration; this task does not fix that
gap, it consumes whatever the network module outputs, same as `modules/eks`/`modules/api-gateway`
already do)
**Requirement**: R-02 (resolution)

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] `aws_eks_node_group.kafka` scaling_config min=1/max=1/desired=1
- [ ] `instance_types = ["t4g.small"]`, `capacity_type = "ON_DEMAND"`
- [ ] Node labeled (e.g. `workload=kafka`) for T5's `nodeSelector`
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T3: Security group rules for Kafka broker traffic

**What**: `aws_security_group_rule` (or a dedicated SG) allowing TCP 9092 (Kafka broker port)
inbound from the EKS cluster's own security group only — no external ingress.
**Where**: `modules/kafka/security.tf`
**Depends on**: T2
**Reuses**: `module.eks`'s cluster security group (existing resource, referenced not recreated)
**Requirement**: spec.md Out of Scope ("no SASL/mTLS — cluster-internal traffic only") — this rule
is what actually enforces that boundary at the network layer

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] Ingress rule scoped to cluster SG only, port 9092, no `0.0.0.0/0`
- [ ] Checkov passes with no new suppressed findings (if a finding requires suppression, document why inline)
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T4: Strimzi operator Helm release

**What**: `helm_release.strimzi_operator` installing the Strimzi Kafka Operator into a new
`kafka` namespace.
**Where**: `modules/kafka/helm.tf`
**Depends on**: T3
**Reuses**: none — first `helm_release` resource in this repo (confirm the `helm` Terraform
provider is already declared in `providers.tf`; add it here if not, that's part of this task, not
a separate one — one file change, still cohesive)
**Requirement**: design.md Tech Decisions ("Strimzi — tentative")

**Tools**:
- MCP: `context7` (confirm current Strimzi Helm chart name/repo/version — do not guess a version number)
- Skill: NONE

**Done when**:
- [ ] `helm_release.strimzi_operator` targets the correct chart repo/version (confirmed via Context7, not assumed)
- [ ] `kubernetes_namespace.kafka` created first (or via `create_namespace = true` on the release)
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T5: Kafka custom resource (KRaft mode, single broker)

**What**: `kubernetes_manifest` (or `kubectl_manifest`, whichever this repo's providers already
support — check `providers.tf` before adding a new provider) applying a Strimzi `Kafka` CR:
KRaft mode (no ZooKeeper), 1 broker, `nodeSelector`/toleration targeting T2's node group, storage
class backed by the node's local/EBS disk (not EFS — this is the entire point of T1/T2).
**Where**: `modules/kafka/kafka-cluster.tf`
**Depends on**: T4
**Reuses**: T2's node label for scheduling
**Requirement**: R-01, R-02 (resolution)

**Tools**:
- MCP: `context7` (confirm current Strimzi `Kafka` CR schema for KRaft mode — this is new/evolving API surface, do not fabricate field names)
- Skill: NONE

**Done when**:
- [ ] `Kafka` CR applies successfully (`kubectl get kafka -n kafka` shows `Ready`) — verify manually post-apply, this can't be gate-checked by `terraform validate` alone since CR correctness is only provable at apply time
- [ ] Broker pod scheduled on the T2 node group, not Fargate (confirm via `kubectl get pod -o wide`)
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

**Commit**: `feat(kafka): provision KRaft single-broker Kafka cluster on dedicated node group`

---

### T6: KafkaTopic CRDs [P]

**What**: 5 `kubernetes_manifest` `KafkaTopic` resources (one Terraform file, `for_each` over a
list — one cohesive deliverable): `notification-requested`, `notification-requested-retry-5s`,
`notification-requested-retry-1m`, `notification-requested-retry-10m`,
`notification-requested-dlq`.
**Where**: `modules/kafka/topics.tf`
**Depends on**: T5
**Reuses**: exact topic names from `rentifyx-communications-api/.specs/features/e04-f09-reliability/design.md`
— read that file before writing this task's names, do not re-derive from memory
**Requirement**: R-03

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] All 5 `KafkaTopic` CRs match comms-api's F-09 topic names exactly (verified against that repo's design.md, not assumed)
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T7: SSM parameter publish [P]

**What**: `aws_ssm_parameter.kafka_bootstrap_servers` (`String` type, path
`/rentifyx/platform/kafka/bootstrap-servers`, value = the Kafka Service's internal DNS
bootstrap address).
**Where**: `modules/kafka/ssm.tf`
**Depends on**: T5
**Reuses**: none — first SSM-publish in this repo (ADR-005 was referenced in the plan doc but
never actually implemented anywhere yet)
**Requirement**: R-04

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] Parameter published at the exact path both consumer repos will read
- [ ] `type = "String"` (not `SecureString` — matches design.md's no-auth decision)
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T8: Module outputs [P]

**What**: `outputs.tf` exposing `bootstrap_servers` and `ssm_parameter_path` from `modules/kafka/`.
**Where**: `modules/kafka/outputs.tf`
**Depends on**: T5
**Reuses**: `modules/eks/outputs.tf`'s existing single-output-per-file style as the precedent
**Requirement**: design.md Components ("Output: `bootstrap_servers`")

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] Both outputs defined, correctly typed
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

---

### T9: Wire `modules/kafka` into `prod/main.tf`

**What**: Add `module "kafka"` block to `prod/main.tf`, positioned after `module.eks` (same
dependency-ordering convention already used by `module.api_gateway`/`module.observability`).
**Where**: `prod/main.tf`
**Depends on**: T6, T7, T8
**Reuses**: existing composition pattern in this exact file
**Requirement**: R-06

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] `module.kafka` block added, inputs wired from `module.eks`/`module.network` outputs
- [ ] `terraform plan` (not just `validate`) runs clean against real AWS creds — this is the first
      point where the whole composition can actually be plan-checked end to end, do this manually
      before considering the task done, not just CI's `validate`
- [ ] Gate check passes: `terraform fmt -check && terraform validate && tflint --module && checkov -d .`

**Tests**: none
**Gate**: build

**Commit**: `feat(kafka): compose kafka module into prod environment`

---

### T10: ADR — Fargate storage limitation & self-hosted Kafka decision [P]

**What**: New ADR file documenting design.md's "R-02 Resolution" section (EBS impossible on
Fargate, EFS unsafe for Kafka per KAFKA-13995, decision = dedicated EC2 node group) and the
Kafka-for-learning-not-cost decision confirmed with the user 2026-07-15.
**Where**: `docs/adr/` (first real ADR file in this repo — `docs/adr/README.md` is currently a
placeholder; follow whatever numbering that README implies, or start at `001` if genuinely empty)
**Depends on**: None (documentation, no code dependency — can run any time, grouped into Phase 3
here only for narrative flow with T9, not a real blocker)
**Reuses**: design.md's own "R-02 Resolution" and "Tech Decisions" sections as source material —
this task transcribes/formalizes, does not re-derive
**Requirement**: R-05

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] ADR documents: context (Fargate can't do EBS, EFS's KAFKA-13995 crash risk), decision (EC2
      node group + KRaft single broker), consequences (~$14/mo, breaks "no idle EC2" goal — stated
      explicitly, not glossed over), and the cost-vs-learning trade-off confirmed with the user
- [ ] `docs/adr/README.md` updated to list the new ADR if that file maintains an index

**Tests**: none
**Gate**: none (documentation only, not `.tf` — outside the Terraform CI workflow's path filter)

---

## Parallel Execution Map

```
Phase 1 (Sequential):
  T1 ──→ T2 ──→ T3

Phase 2 (mostly sequential — each step needs the previous cluster state):
  T3 ──→ T4 ──→ T5 ──┬──→ T6 [P] ─┐
                      └──→ T7 [P] ─┤
                      └──→ T8 [P] ─┤
                                    │
Phase 3:                           ▼
  T6, T7, T8 ──→ T9
  (no dependency) ──→ T10 [P] (can start any time)
```

---

## Task Granularity Check

| Task | Scope | Status |
|---|---|---|
| T1: Node group IAM role | 1 role + 3 attachments, 1 file | ✅ Granular |
| T2: EC2 managed node group | 1 resource, 1 file | ✅ Granular |
| T3: Security group rules | 1-2 resources, 1 file | ✅ Granular |
| T4: Strimzi operator Helm release | 1 helm_release + namespace, 1 file | ✅ Granular |
| T5: Kafka CR | 1 manifest resource, 1 file | ✅ Granular |
| T6: KafkaTopic CRDs | 5 resources via for_each, 1 file, cohesive | ✅ Granular (2-3+ related things in same file, cohesive per Tips guidance) |
| T7: SSM parameter | 1 resource, 1 file | ✅ Granular |
| T8: Module outputs | 2 outputs, 1 file | ✅ Granular |
| T9: prod/main.tf wiring | 1 module block, 1 file (modified) | ✅ Granular |
| T10: ADR | 1 doc file | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
|---|---|---|---|
| T1 | None | (start) | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T2 | T2 → T3 | ✅ Match |
| T4 | T3 | T3 → T4 | ✅ Match |
| T5 | T4 | T4 → T5 | ✅ Match |
| T6 | T5 | T5 → T6 [P] | ✅ Match |
| T7 | T5 | T5 → T7 [P] | ✅ Match |
| T8 | T5 | T5 → T8 [P] | ✅ Match |
| T9 | T6, T7, T8 | T6,T7,T8 → T9 | ✅ Match |
| T10 | None | independent branch → T10 [P] | ✅ Match |

---

## Test Co-location Validation

No TESTING.md exists — this repo's only automated gate is the Terraform CI workflow
(`fmt`/`validate`/`tflint`/`checkov`), which every task already requires under `Gate: build`.
There is no unit/integration/e2e test framework applicable to Terraform HCL, so `Tests: none` is
correct for all 10 tasks per the coverage-matrix fallback rule ("Tests: none is only valid when
the coverage matrix says none for that code layer" — here, no matrix exists and the only
verifiable layer is "does Terraform validate/lint/security-scan clean").

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
|---|---|---|---|---|
| T1–T9 | Terraform HCL / Helm / K8s manifests | none (no test framework for IaC in this repo) | none | ✅ OK |
| T10 | Markdown doc | none | none | ✅ OK |

---

## Tools Question for User

For each task, which tools should I use beyond what's already specified above (Context7 flagged
on T4/T5 for Strimzi chart/CRD schema verification — required, not optional, since Strimzi's
KRaft-mode API surface is new/evolving and must not be guessed)? No other MCPs/skills are assumed
— confirm before Execute starts.
