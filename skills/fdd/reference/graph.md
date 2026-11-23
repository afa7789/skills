# Graph: brief or evidence → `features/graph.yaml`

Input: the brief for a new repo, or `features/evidence.yaml` for an existing one. Inspect the repo and original sources whenever evidence is missing. Do not modify application code.

## Rules

- The graph is canonical. Code, tests, docs and history are evidence for it, not authorities over it.
- Describe PRODUCT BEHAVIOR and how features relate. A feature that is a synonym for a directory or module is wrong.
- Resolve contradictions yourself when evidence supports a reasonable conclusion. Do not default to code over docs, docs over code, newer commits over older, tests over intent, or old notes over current architecture. Pick the reading that explains the whole project most coherently. Prefer later explicit decisions that clearly supersede earlier ones.
- Separate intended, current, legacy, incomplete, accidental and planned-never-built behavior (`behavior_kind`).
- Meaningful ambiguity: choose the most plausible reading and record a `decision` block. Stop only if continuing would make the graph fundamentally unreliable.
- Write each acceptance criterion as an observable outcome (input → output) that a command can check, never a quality wish.
- Keep it concise.

## Schema

```yaml
schema_version: 1
features:
  - id: F-001                # F-NNN, stable, never reused
    name: Login with email and password
    purpose: Why the product needs it.
    expected_behavior: |
      What a user or caller observes.
    acceptance_criteria:
      - POST /login with valid credentials returns 200 and a session cookie
      - POST /login with a wrong password returns 401
    dependencies: []         # features that must work first
    related_features: [F-002]
    relevant_code: []        # evidence, path:line
    relevant_tests: []
    relevant_docs: []
    status: not_implemented  # not_implemented | partial | implemented | legacy | accidental | abandoned
    behavior_kind: intended  # intended | current | legacy | incomplete | accidental | planned_never_built
    confidence: low          # high | medium | low
    decision:                # required when confidence is low, omitted otherwise
      question: Which session lifetime is intended?
      confidence: low
      reasoning: Two sources disagree and neither supersedes the other.
      alternatives:
        - 1h, as the code does
        - 24h, as the README says
```

New repo: every feature starts as `status: not_implemented`, `behavior_kind: intended`, with empty `relevant_*` lists.
