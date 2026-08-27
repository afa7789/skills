# Engineering Standards (Non-Negotiable)

Apply the following principles throughout **every phase** of the roadmap. These are hard constraints, not suggestions:

## Scope & precedence

These standards govern **how the code you write must be built**. They never mandate building more than the task asks for. When a standard appears to conflict with the ponytail ladder (the lazy-senior-dev ladder in `agents/architect.md` and `agents/builder.md`), resolve it by scope:

| Situation | Precedence |
|---|---|
| Explicitly requested by the user, or listed under PLAN.md Success Criteria | **Standard wins.** Build it, no re-arguing. |
| Greenfield scaffolding (new repo, new service) | **Standards apply in full.** |
| Change inside an existing codebase | **Ladder decides what gets added**; standards govern how what you add is written. |
| One-off script, spike, or throwaway | KISS and a runnable check only. Skip Makefile, coverage gate, adapter layers. |

Concretely: the swappable database adapter is required when a swappable provider is a stated requirement — not in every project that happens to store data. Coverage ≥ 90% applies to the modules the task touches, not as a mandate to backfill tests for untouched code. DRY means extract on the **second** duplication, not in anticipation of one.

| Principle | Expectation |
|---|---|
| **DRY** | No duplicated logic. Extract shared behavior into utilities, helpers, or base abstractions. |
| **KISS** | Favor the simplest solution that works. Avoid over-engineering. |
| **SOLID** | Apply all five principles — especially Dependency Inversion for infrastructure layers. |
| **SoC** | Clear separation between transport, business logic, domain, and data layers. |
| **TDD** | Tests are written before or alongside implementation — never after. |
| **Coverage ≥ 90%** | Unit + integration coverage must meet or exceed 90%. |
| **Clean Architecture** | The database provider must be swappable (Postgres, MySQL, CockroachDB, etc.) via interface/adapter — only the initially scoped providers will be implemented, but the structure must support future additions with zero core changes. |
| **Caching** | If the product is web-based, implement caching strategy (HTTP cache headers, Redis, in-memory, etc.) where appropriate. |
| **CI/CD Pipeline** | Must include: `lint → format → test → coverage report`. Fail fast on any violation. |
| **Makefile** | Provide targets at minimum: `build`, `run`, `clean`, `lint`, `test`. |
| **Test folder mirroring** | The test directory must mirror the source directory tree exactly. |
| **Registration proof** | Every route, endpoint, command and subscriber has a test that resolves it through the **composed** app — not only a unit test on the handler. A handler test passes whether or not the handler is mounted. |
| **Identity & uniqueness** | Reusable-entity identity is normalized at write time (trim, case-fold, collapse whitespace, Unicode NFC) **and** enforced by a database unique index on the normalized value. An application-level duplicate check is a race, not a constraint. |

## Measurable gates

A sharp, checkable constraint beats a vague instruction. "Write clean code" is a bias; "the linter exits 0 with the complexity rule enabled" is a gate. Gates change how code gets generated (guard clauses, early returns, table-driven logic); biases get ignored.

| Rule | Expectation |
|---|---|
| **Lint gate, always** | Every code change passes the project's linter **with a per-function complexity rule enabled** before it is marked done. Run the linter, read the failure, fix it — prompt-only intent is not enforcement. |
| **Default ceilings** | Per-function cyclomatic/cognitive complexity ≤ 10 unless the project sets otherwise. Tool + config per stack: [typescript](typescript.md), [rust](rust.md), [python](python.md), [golang](golang.md). |
| **Simplify flow, don't split to dodge** | The ceiling is per-function; splitting one messy function into five trivial ones to pass the metric is gaming it. Prefer genuinely simpler control flow: early returns, guard clauses, decision tables, extracted predicates. |
| **Readability wins ties** | Complexity counts paths, not clarity. Dense boolean golf that passes lint but reads worse is a defect, not a pass. |
