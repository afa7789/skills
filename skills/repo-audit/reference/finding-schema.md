# Finding schema v1.0

The audit output is **valid, machine-readable YAML**. No introduction, no conclusion, no explanation, no Markdown outside the YAML document.

Other agents consume this, so:

- use stable field names;
- do not change the schema arbitrarily;
- use arrays even with a single element;
- use `null` when something cannot be determined;
- never invent missing values;
- keep paths relative to the repository root;
- keep descriptions objective, no decorative text;
- do not use severity to represent priority;
- do not use priority to represent confidence.

---

## Structure

```yaml
audit:
  version: "1.0"

  scope:
    repository: "."
    mode: "full"
    base: null
    head: null
    agents_used: 9
    scopes:
      - agent: 1
        scope: ""
      - agent: 2
        scope: ""

  summary:
    total_findings: 0

    by_severity:
      critical: 0
      high: 0
      moderate: 0
      low: 0
      informational: 0

    by_category:
      correctness: 0
      security: 0
      reliability: 0
      maintainability: 0
      architecture: 0
      performance: 0
      observability: 0
      testing: 0
      type_safety: 0
      contract_consistency: 0
      documentation: 0
      developer_experience: 0
      dependency_hygiene: 0
      configuration_hygiene: 0
      legacy: 0
      dead_code: 0
      duplication: 0
      over_engineering: 0
      simplification: 0

  findings:
    - id: "AUDIT-001"

      title: ""

      category: "maintainability"

      secondary_categories: []

      severity: "moderate"

      priority: "medium"

      confidence: "high"

      status: "actionable"

      pre_existing: null

      scope:
        agent: 1
        area: ""

      locations:
        - path: ""
          symbol: null
          lines: null

      evidence:
        - ""

      current_behavior: ""

      problem: ""

      impact:
        description: ""
        affected_areas: []
        failure_modes: []

      root_cause: null

      recommendation:
        action: ""
        rationale: ""
        change_type: "modify"

      alternatives: []

      removable:
        files: []
        symbols: []
        dependencies: []
        configuration: []
        abstractions: []

      estimated_effect:
        complexity: "decrease"
        maintenance_surface: "decrease"
        runtime_behavior: "unchanged"
        code_size: null

      risk:
        level: "low"
        description: ""

      dependencies:
        blocked_by: []
        blocks: []
        related_findings: []

      validation:
        required: true
        steps: []

  cross_cutting_findings:
    - id: "CROSS-001"
      title: ""
      category: "architecture"
      severity: "moderate"
      confidence: "high"
      affected_findings: []
      affected_areas: []
      description: ""
      recommendation: ""

  conflicts:
    - id: "CONFLICT-001"
      agents: []
      subject: ""
      positions: []
      resolution: null
      requires_human_review: true

  unresolved:
    - id: "UNRESOLVED-001"
      subject: ""
      reason: ""
      locations: []
      required_information: ""

  metrics:
    potentially_removable:
      files: null
      abstractions: null
      dependencies: null
      configuration_entries: null
      execution_paths: null

    estimated_maintenance_surface_change: null

  audit_coverage:
    reviewed_paths: []
    skipped_paths: []
    excluded_paths: []
    limitations: []
```

---

## `category`

The primary kind of problem. Allowed values:

```yaml
- correctness
- security
- reliability
- maintainability
- architecture
- performance
- observability
- testing
- type_safety
- contract_consistency
- documentation
- developer_experience
- dependency_hygiene
- configuration_hygiene
- legacy
- dead_code
- duplication
- over_engineering
- simplification
```

Use `secondary_categories` when the finding belongs to more than one:

```yaml
category: "correctness"
secondary_categories:
  - "contract_consistency"
  - "type_safety"
```

## `severity`

Technical impact if the problem stays. Allowed values: `critical`, `high`, `moderate`, `low`, `informational`.

- `critical` — serious security risk, data loss, corruption or systemic failure;
- `high` — relevant bug or important operational risk;
- `moderate` — significant maintenance, architecture, reliability or consistency problem;
- `low` — localized improvement with limited impact;
- `informational` — valid observation needing no immediate change.

A simplification opportunity does **not** automatically get low severity.

## `priority`

Recommended execution order. Allowed values: `immediate`, `high`, `medium`, `low`, `defer`.

Weigh impact, risk, effort, dependencies, ease of validation, and how many problems the change eliminates at once.

## `confidence`

How well the evidence supports the finding: `high`, `medium`, `low`. Independent of severity and priority.

## `status`

Allowed values: `actionable`, `needs_investigation`, `needs_human_decision`, `not_recommended`.

Never force a recommendation when the evidence is insufficient.

## `mode`, `base`, `head`

`scope.mode` is `full` or `diff`.

- `full` — the whole repository was audited. `base` and `head` are `null`.
- `diff` — only a change was audited. `base` and `head` hold the resolved refs or SHAs of the audited range.

## `pre_existing`

`null` in `full` mode. In `diff` mode it is mandatory on every finding:

- `false` — the change introduces the problem, worsens it, fails to remove something its own change made dead, or contradicts something outside it. **This is the set a PR review acts on.**
- `true` — the problem existed before the change and the change merely sits near it. Report it as `severity: informational`, `status: needs_investigation`. Never count it against the change.

## `change_type`

Allowed values:

```yaml
remove
consolidate
inline
modify
replace
document
test
configure
investigate
retain
```

Use `retain` when something looked complex, was analyzed, and is justified. This stops later agents from removing abstractions that have a legitimate reason to exist:

```yaml
recommendation:
  action: "Keep the boundary."
  rationale: "It isolates an external payment provider and is substituted by the integration test suite."
  change_type: "retain"
```

## `estimated_effect`

- `complexity`, `maintenance_surface`: `decrease` | `unchanged` | `increase`;
- `runtime_behavior`: `unchanged` | `changed` | `unknown`;
- `code_size`: an approximate figure, or `null` when there is no basis.

## `risk.level`

`low` | `medium` | `high`.

---

## Mandatory evidence

No finding may exist on architectural preference alone. Every finding cites concrete evidence: implementation, call sites, dependency graph, imports, exports, configuration, tests, documentation, history present in the code, executable behavior, or verifiable absence of consumers.

Avoid:

```yaml
evidence:
  - "This seems unnecessarily complex."
```

Prefer:

```yaml
evidence:
  - "PaymentProvider has one implementation and one consumer."
  - "The interface is not exported outside packages/payments."
  - "No test substitutes another implementation."
```

## Cross-cutting findings

Use `cross_cutting_findings` when several findings are symptoms of one structural cause — three competing representations of the same domain, a repeated pattern of wrappers with no responsibility, documentation and code using different names, an incomplete migration spread across the repo, configuration duplicated across services.

Do not replicate the same recommendation across dozens of findings when it can be represented once as a cross-cutting problem.

## Relations between findings

```yaml
dependencies:
  blocked_by:
    - "AUDIT-014"
  blocks:
    - "AUDIT-027"
  related_findings:
    - "AUDIT-008"
```

This lets later agents build an execution order. Every referenced id must exist in the document.

## Metrics

Final metrics are estimates, not targets. Do not change code merely to increase removed LOC, removed files or removed abstractions. With insufficient evidence, write `files: null` instead of inventing a number.

---

## Final criterion

Do not produce a "Top 10". Do not arbitrarily keep only the largest findings.

Preserve every relevant finding in `findings`, with enough metadata for another agent to filter, order, group, prioritize, validate, and build an implementation plan.

The audit produces **structured data about the state of the repository**, not an editorialized refactor plan.
