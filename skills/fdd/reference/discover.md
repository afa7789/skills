# Discover: existing repo → `features/evidence.yaml`

Reconstruct what the project is meant to do from imperfect, contradictory evidence. Read only. Modify nothing.

## Sources

Inspect all of them: code, tests, docs, config, schemas, migrations, scripts, provided text files, exported commit history, architecture notes, TODOs and comments.

Any source may be incomplete, outdated, misleading or wrong. The code is not the spec. The docs are not the spec. Commit messages do not prove the final state.

## Weighing evidence

Reason from the whole body of evidence:

- recency, and later explicit decisions superseding earlier ones
- agreement across independent sources
- actual implementation and test behavior
- architectural coherence
- intent repeated in notes or history
- whether code looks unfinished, transitional, experimental or legacy

## Output

One entry per product behavior. Never discard a contradiction silently.

```yaml
behaviors:
  - name: Login with email and password
    evidence: [src/auth/login.rs:12, README.md:40]   # path:line
    intended: Valid credentials open a session; invalid ones get 401.
    implementation: [src/auth/login.rs]
    tests: [tests/login.rs]
    docs: [README.md:40]
    depends_on: [Session store]
    state: complete        # complete | partial | abandoned | legacy
contradictions:
  - claims: [README says sessions last 24h, code expires them at 1h]
    sources: [README.md:52, src/auth/session.rs:8]
    interpretation: 1h is intended; README is stale.
    reasoning: Later commit "shorten session ttl" plus a test asserting 1h.
    confidence: medium     # high | medium | low
```

Keep it concise and machine-readable. It is the input for `reference/graph.md`.
