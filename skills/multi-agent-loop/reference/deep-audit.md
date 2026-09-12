# Deep Audit — `repo-audit`

The Phase 2 checklist finds what is **missing**. It never finds what is **excessive** — dead
abstractions, legacy paths with no consumer, config with one valid value, duplicated
representations. For that, run the `repo-audit` skill in **FULL mode** (repo-wide; its DIFF mode
is for PR review, not for this pass).

**Trigger — all four must hold:**

1. dagRobin is quiescent;
2. the Phase 2 checklist produced **no** TYPE A gap;
3. `.claude/AUDIT_RAN` does not exist — the audit runs **at most once per loop run**;
4. the repo has real code (not a fresh scaffold with one commit).

**Procedure:**

```bash
test -f .claude/AUDIT_RAN || {
  # run the `repo-audit` skill -> writes .claude/AUDIT.yaml
  date -u +%FT%TZ > .claude/AUDIT_RAN
}
```

Once per run, also dispatch **summarizer-auditor** to audit `.claude/` (`WATCHDOG.md`,
`FALSE_POSITIVES.md`, `IMPROVEMENTS.md`) for staleness.

**Import filter — this is what keeps the loop finite.** From `.claude/AUDIT.yaml`, create
dagRobin tasks ONLY for findings matching:

```
status: actionable
AND confidence: high
AND priority in {immediate, high}
AND change_type != retain
```

Map each imported finding: `id` → task id, `title` → description, `recommendation` + `evidence`
+ `locations` → `metadata.long-description`, `dependencies.blocked_by` → `--deps`, `severity` →
priority (critical/high → 1, moderate → 2, low → 3). These are TYPE A.

Everything else is routed, never re-discovered:

| Finding | Destination |
|---|---|
| `change_type: retain`, `status: not_recommended` | `.claude/FALSE_POSITIVES.md` — so the next run never proposes deleting it |
| `status: needs_human_decision`, `conflicts:`, `unresolved:` | TYPE C — record, create no task |
| anything below the import filter | `.claude/IMPROVEMENTS.md` |
| `category: documentation` findings | `.claude/IMPROVEMENTS.md`, plus offer the `docs-audit` skill in the final report |

**Guards.** `repo-audit` always finds something — that is what it is for, and it is exactly how a
loop stops terminating. So: once per run, hard-filtered import, and a finding rejected into
`FALSE_POSITIVES.md` never comes back. A filtered import that yields zero tasks is the expected
outcome — proceed to Hard Stop, do not lower the filter.
