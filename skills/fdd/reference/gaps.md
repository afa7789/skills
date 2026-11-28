# Gaps: existing repo vs graph → `features/gaps.yaml`

Audit the whole project against `features/graph.yaml` as the canonical spec. Read only. Modify nothing.

Inspect code, tests, docs, config, schemas, migrations, scripts and supporting artifacts. For EVERY feature, decide whether the project:

- implements it correctly, partially, or in contradiction
- lacks required behavior, or has broken or incomplete flows
- lacks tests, or has wrong or misleading tests (flag `TEST_GAP` only when the project uses tests or the user asked)
- has stale docs or undocumented behavior
- keeps legacy code that conflicts with the graph
- carries complexity that hides the intended behavior

Trace cross-feature impact: a problem in one feature that breaks its dependents or related features.

## Classes

| Class | Meaning |
|---|---|
| `BLOCKER` | The feature cannot meet its expected behavior, or it blocks dependents. |
| `INCORRECT` | Implemented behavior contradicts the graph. |
| `INCOMPLETE` | Required behavior is missing or unfinished. |
| `TEST_GAP` | Expected behavior lacks sufficient verification (only when the project uses tests or the user asked). |
| `DOC_GAP` | Docs disagree with canonical behavior or fail to describe it. |
| `LEGACY` | Behavior is obsolete or contradicts the canonical system. |
| `IMPROVEMENT` | Not required, but materially improves simplicity, maintainability, reliability, clarity or consistency. |

## Finding schema

```yaml
findings:
  - id: G-001
    feature: F-001
    class: INCOMPLETE
    description: Wrong password returns 500 instead of 401.
    evidence: [src/auth/login.rs:40, tests/login.rs:12]
    files: [src/auth/login.rs]
    expected: 401 with an error body
    observed: panic on unwrap, 500
    confidence: high       # high | medium | low
    impact: [F-002]        # downstream features, when applicable
```

Features with no findings get no entry. Keep it machine-readable. It is the input for `reference/plan.md`.
