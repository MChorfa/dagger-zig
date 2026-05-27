# Incident Response Runbook

## Severity Levels

| Level             | Criteria                                         | Response Time | Notification                    |
| ----------------- | ------------------------------------------------ | ------------- | ------------------------------- |
| **P0 (Critical)** | Security breach, data loss, complete outage      | 15 min        | Page on-call + Slack #incidents |
| **P1 (High)**     | Major feature degraded, potential security issue | 1 hour        | Slack #incidents + email        |
| **P2 (Medium)**   | Partial degradation, minor security concern      | 4 hours       | Slack #incidents                |
| **P3 (Low)**      | Cosmetic issues, documentation gaps              | 24 hours      | GitHub issue                    |

## Incident Commander

First responder becomes Incident Commander (IC) and:

1. Acknowledges incident in PagerDuty/Opsgenie
2. Creates incident channel: `#inc-YYYY-MM-DD-brief-description`
3. Notifies stakeholders per severity level
4. Appoints roles:
   - **Scribe**: Documents timeline in incident doc
   - **Comms**: External communications (if needed)
   - **Engineer**: Technical investigation

## Runbooks

### P0: Security Breach

**Symptoms**: Unauthorized access detected, secret exposed, unexpected privilege escalation

1. **Immediate (0-15 min)**

   ```bash
   # 1. Isolate affected systems
   dagger call -m ci disable-module --name=<affected-module>

   # 2. Rotate exposed secrets
   gh secret set API_KEY --body="$(openssl rand -hex 32)"

   # 3. Revoke signing keys if compromised
   cosign clean --force <key-id>
   ```

2. **Assessment (15-60 min)**
   - Review audit logs: `dagger call audit-logs --since=24h`
   - Identify scope of exposure
   - Check for lateral movement

3. **Recovery (1-4 hours)**
   - Patch vulnerability
   - Redeploy with rotated credentials
   - Verify no backdoors remain

4. **Post-Incident**
   - File security advisory
   - Complete post-mortem within 24h
   - Update security controls

### P1: Build Pipeline Failure

**Symptoms**: CI failing, builds not producing artifacts, SLSA violations

1. **Immediate**

   ```bash
   # Check Dagger engine status
   dagger call -m ci health-check

   # Verify SLSA provenance
   slsa-verifier verify-artifact --provenance-path ...
   ```

2. **Common Causes**

   | Error                | Solution                        |
   | -------------------- | ------------------------------- |
   | `timeout`            | Increase `DAGGER_CLOUD_TIMEOUT` |
   | `permission denied`  | Check `DAGGER_CLOUD_TOKEN`      |
   | `provenance invalid` | Re-run SLSA workflow            |
   | `signature failed`   | Check Sigstore availability     |

### P2: Performance Degradation

**Symptoms**: Slow operations, high latency, cache misses

1. **Diagnosis**

   ```bash
   # Check cache hit rate
   dagger call -m ci metrics --metric=cache_hit_rate

   # Review traces in Jaeger
   open http://jaeger.localhost:16686
   ```

2. **Mitigation**
   - Scale Dagger engine horizontally
   - Warm caches with `dagger call -m ci warm-cache`
   - Enable distributed caching

### P3: Documentation Issue

**Symptoms**: Broken links, outdated examples, unclear API

1. Fix in branch: `docs/fix-<issue>`
2. Preview: `mdbook serve docs/`
3. PR with `docs:` prefix

## Communication Templates

### Internal (Slack)

```
:rotating_light: **INCIDENT DECLARED** :rotating_light:

**Severity**: P{0-3}
**System**: {dagger-zig/sdk/ci}
**Impact**: {description}
**Started**: {timestamp}
**Channel**: #inc-{date}-{brief}
**IC**: @{handler}

**Current Status**: {investigating/identified/mitigating/resolved}
```

### External (Status Page)

```
**Status**: Degraded Performance
**Component**: Dagger Zig SDK
**Duration**: 45 minutes
**Impact**: Schema validation delays
**Resolution**: Cache layer restored, monitoring improvements deployed
```

## Tooling

| Tool      | Purpose                 | Command                               |
| --------- | ----------------------- | ------------------------------------- |
| PagerDuty | On-call paging          | `pd incident:create --title="..."`    |
| Slack     | Communication           | `/incident declare`                   |
| Dagger    | Diagnostics             | `dagger call -m ci incident-diagnose` |
| Sigstore  | Signature verification  | `cosign verify ...`                   |
| SLSA      | Provenance verification | `slsa-verifier verify-artifact ...`   |

## Recovery Procedures

### Rollback Release

```bash
# 1. Identify last known good
gh release list --limit=5

# 2. Mark bad release
cosign sign --tlog-upload=false \
  --yes \
  --annotation "revoked=true" \
  ghcr.io/mchorfa/dagger-zig:v0.1.1

# 3. Update latest tag
crane tag ghcr.io/mchorfa/dagger-zig:v0.1.0 latest
```

### Restore from Backup

```bash
# Source code (Git)
git revert --no-commit HEAD~{n}

# Artifacts (if needed)
gh run download --repo=mchorfa/dagger-zig <run-id>
```

## Post-Mortem Template

```markdown
# INCIDENT-XXX: [Brief Title]

## Metadata

- Date: YYYY-MM-DD
- Duration: XX minutes
- Severity: P{0-3}
- IC: @name
- Participants: @names

## Summary

One paragraph describing what happened and impact.

## Timeline

- 09:00 UTC - Issue detected via alert
- 09:15 UTC - IC paged, incident declared
- 09:30 UTC - Root cause identified
- 10:00 UTC - Mitigation deployed
- 10:30 UTC - Service fully recovered
- 11:00 UTC - Incident resolved

## Root Cause

Detailed explanation of why the incident occurred.

## Impact

- Users affected: XX%
- Data lost: none/YY records
- Services degraded: list

## Lessons Learned

1.
2.

## Action Items

| ID  | Task | Owner | Due |
| --- | ---- | ----- | --- |
| 1   |      |       |     |

## Follow-Up

- [ ] Action items completed
- [ ] Monitoring improvements deployed
- [ ] Runbook updated
- [ ] Team retro scheduled
```

## Contact Information

| Role             | Primary             | Backup               |
| ---------------- | ------------------- | -------------------- |
| Security Lead    | security@MChorfa.io | pagerduty escalation |
| Engineering Lead | mchorfa@MChorfa.io  | pagerduty escalation |
| On-Call Engineer | PagerDuty rotation  | secondary rotation   |

## Revision History

| Date       | Author  | Changes         |
| ---------- | ------- | --------------- |
| 2024-06-15 | mchorfa | Initial version |
