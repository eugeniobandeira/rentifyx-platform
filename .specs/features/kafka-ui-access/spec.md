# Kafka UI Access Specification

## Problem Statement

MSK Serverless has no topic/message/consumer-group visibility in the AWS Console at all ("Topic management requires Amazon MSK Provisioned... Serverless clusters are currently not supported" — confirmed directly against the real cluster, 2026-07-20). During this session's end-to-end deploy work, every Kafka inspection (listing topics, checking consumer group state, diagnosing the `GroupCoordinator Access Denied` bug) required writing and running one-off scripts. A persistent, real UI (`kafka-ui`/`kafbat-ui`) removes that friction for all future debugging.

## Goals

- [ ] Browse topics, partitions, messages, and consumer group state on the real MSK Serverless cluster from a web UI
- [ ] Zero new public network exposure — no ALB, no public port, no new inbound security group rule
- [ ] Reuse infrastructure that already exists (an app repo's EC2 instance) rather than provisioning a dedicated host

## Out of Scope

| Feature | Reason |
|---|---|
| Public/always-on access (ALB, fixed domain) | User explicitly chose the SSH-tunnel option over ALB — this is an occasional debugging tool, not a product surface |
| Message production/editing from the UI | Read/inspect only; kafka-ui's write features are not needed and widen the IAM policy unnecessarily |
| Dedicated EC2 instance for kafka-ui | User explicitly chose "container on an existing EC2" over a dedicated instance |
| Automatic teardown/lifecycle tied to `terraform destroy` | kafka-ui is a Docker container started by a script, not a Terraform-managed resource — this session's pattern of `terraform destroy` at the end already removes the underlying EC2 instance it runs on |

---

## User Stories

### P1: Inspect the real Kafka cluster from a browser ⭐ MVP

**User Story**: As the developer operating this system, I want a web UI showing topics/partitions/consumer groups/messages on the real MSK Serverless cluster, so that I don't have to write a one-off script every time I need to check Kafka state.

**Why P1**: This is the entire point of the feature — without it, nothing has changed from this session's workaround pattern.

**Acceptance Criteria**:

1. WHEN the developer runs the provided startup script on an app repo's EC2 instance THEN the system SHALL start a `kafka-ui` (kafbat-ui) Docker container authenticated to the real MSK Serverless cluster via SASL/IAM
2. WHEN the container starts THEN the system SHALL use the EC2 instance's own IAM role for authentication (no static AWS credentials in the container's config)
3. WHEN the developer opens an SSH local-port-forward to the instance and browses to `localhost:<forwarded-port>` THEN the system SHALL show the real topic list, partition counts, and consumer group states from the actual cluster
4. WHEN the developer inspects a topic in the UI THEN the system SHALL show real message contents (subject to Edge Cases below re: sensitive data)

**Independent Test**: Start the container, open the SSH tunnel, load the UI in a browser, confirm the 6 topics from this session's bootstrap tool are visible with correct partition counts.

---

### P2: No new attack surface

**User Story**: As the developer, I want this tool to add zero new ways into the system from the public internet, so that a debugging convenience never becomes a security liability.

**Why P2**: Important but secondary to the tool actually working — a broken security posture is bad, but so is a UI that can't authenticate.

**Acceptance Criteria**:

1. WHEN kafka-ui is running THEN the system SHALL NOT require any new security group ingress rule (SSH tunneling forwards traffic over the existing SSH connection; the UI's own port is never opened to `0.0.0.0/0`)
2. WHEN kafka-ui's IAM permissions are evaluated THEN the system SHALL reuse the EC2 instance's existing `kafka-cluster:*` policy rather than provisioning a separate, wider one
3. WHEN the SSH tunnel is closed THEN the system SHALL make kafka-ui unreachable from the developer's machine (no lingering access path)

**Independent Test**: Attempt to reach the kafka-ui port directly from outside the SSH tunnel (e.g., `curl http://<public-ip>:<port>`) and confirm it fails/times out — the security group has no rule for that port.

---

### P3: Survives instance restart

**User Story**: As the developer, I want kafka-ui to still be running if the EC2 instance reboots mid-debugging-session, so that I don't have to remember to restart it manually.

**Why P3**: Convenience, not correctness — the current session's pattern is "spin up, debug, tear down" in one sitting, so this matters less than P1/P2.

**Acceptance Criteria**:

1. WHEN the EC2 instance restarts THEN the system SHALL bring the kafka-ui container back up automatically (`--restart unless-stopped`, same pattern already used for the app containers)

---

## Edge Cases

- WHEN a topic contains real user PII (e.g., `notification-requested` payloads with recipient email/phone, per LGPD scope already established for this project) THEN the system SHALL still show it in kafka-ui — this tool is developer-only, behind an SSH tunnel requiring the same SSH key as EC2 access already requires, not a broader exposure than what deploying to that EC2 already implies
- WHEN the app repo's EC2 instance is torn down (`terraform destroy`) THEN the system SHALL lose the kafka-ui container along with it — no separate cleanup step is needed since nothing about kafka-ui outlives the host it runs on
- WHEN the MSK cluster doesn't exist yet (no `terraform apply` has been run) THEN the system SHALL fail to start kafka-ui with a clear connection error, not a silent hang — same class of gap as the two other Kafka clients already built this session

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
|---|---|---|---|
| KUI-01 | P1: Inspect cluster | Design | Pending |
| KUI-02 | P1: Inspect cluster | Design | Pending |
| KUI-03 | P1: Inspect cluster | Design | Pending |
| KUI-04 | P1: Inspect cluster | Design | Pending |
| KUI-05 | P2: No new attack surface | Design | Pending |
| KUI-06 | P2: No new attack surface | Design | Pending |
| KUI-07 | P2: No new attack surface | Design | Pending |
| KUI-08 | P3: Survives restart | Design | Pending |

**Coverage:** 8 total, 0 mapped to tasks, 8 unmapped ⚠️ (expected — Design/Tasks phase not run yet)

---

## Success Criteria

- [ ] Developer can list topics, inspect a message, and check a consumer group's lag/state for the real MSK Serverless cluster, using only a browser + one SSH command
- [ ] Zero new Terraform-managed resources required (container is started via a plain `docker run` script, not IaC)
- [ ] Zero new security group rules
