<!-- Framework-agnostic: map each item to the stack under review. -->

# Domain Review Checklist

Work through every section. Skip a section only if the diff clearly has zero relevance to it — **and say so explicitly in the report**.

---

## 1. Security (block on any critical finding)

### Race conditions / concurrency
- [ ] Shared mutable state (balances, counters, inventory, quotas) is read under a lock or inside a transaction (`SELECT ... FOR UPDATE`, `lockForUpdate()`, mutex, optimistic version column with retry)
- [ ] Concurrent request scenarios cannot double-spend, double-submit, or overdraw
- [ ] No check-then-act gap between validation and mutation (an application-level duplicate check is a race, not a constraint — see `identity:` in the wiring lens)
- [ ] Deadlock-prone transaction paths have retry configured
- [ ] State-mutating work is synchronous where ordering matters — only notifications/side-effects go to queues; no `delay()` on critical mutations

### Injection
- [ ] No raw queries with string concatenation/interpolation — parameterized bindings or query builder only
- [ ] No user-controlled data rendered without escaping (template auto-escape on; no raw-output directives with user input)
- [ ] No user input interpolated into shell commands, file paths, or serialized payloads

### Authentication & authorization
- [ ] Every new endpoint/mutation/command has an auth guard — none exposed without middleware
- [ ] Sensitive operations (money movement, account changes, auth actions) are rate-limited server-side
- [ ] Role/permission checks for admin-only operations; not bypassable by manipulating input fields
- [ ] Raw exception messages never returned to clients; errors logged with context (user id, entity id, correlation id)

### Sensitive-data safety (money, credits, points, quotas)
- [ ] Amounts calculated 100% server-side — no client-supplied totals/payouts accepted
- [ ] Audit/journal record created BEFORE the balance/state mutation; audit tables are append-only
- [ ] Server-side limits enforced (max amounts, ceilings)
- [ ] Money columns are `decimal`, never `float`/`double`
- [ ] Randomness for anything adversarial uses a CSPRNG (`random_bytes`, `crypto`), never `rand()`/`time()`
- [ ] No hidden server state leaked to the client mid-flow (game state, answers, other users' data) — check every serializer/resolver that runs while a flow is in progress

---

## 2. Architecture

### Single Source of Truth (blocking)
- [ ] No value re-derived where a function already produces it — the new caller delegates
- [ ] Where two surfaces must agree on a number (admin view vs enforcement, export vs report, resolver vs job), one owns the calculation and the others call it
- [ ] Shared SQL fragments, conversion formulas, and thresholds live in one constant or one method
- [ ] No comment claiming two implementations "must stay in sync" — that is duplication with a comment where an extraction belongs
- [ ] The owner is the lower layer: repository for data access, service for business rules; UI/resolvers/reports call down, never the reverse
- **A second copy of a value an existing function already produces is automatically blocking.** Carve-out: a test may compute an expected value independently of production code — that is a drift guard, not duplication.

### Layering
- [ ] Queries live in the data layer (repositories) — not in controllers, resolvers, UI handlers, or service constructors
- [ ] Resolvers/controllers are thin — delegate immediately; validation in dedicated validator classes
- [ ] Configurable values in settings/config classes, not hardcoded thresholds
- [ ] Queued/async work uses the correct queue; heavy batch work goes to low-concurrency queues

---

## 3. Migrations & Schema (skip if none)

- [ ] Backwards-compatible — old code can still run against the new schema during deploy
- [ ] No column rename without a two-step migration (add → backfill → drop old)
- [ ] No `NOT NULL` added to large tables without a default
- [ ] No drop of columns/tables without verifying zero code references (grep first)
- [ ] Indexes on large tables created non-blocking; no full-table locks in a single migration
- [ ] Idempotent where possible (`hasColumn`/`IF NOT EXISTS` guards)
- [ ] No `update`/`delete` in migrations on transaction/audit tables — append-only
- [ ] Changes to financial/audit-critical tables called out explicitly, regardless of how the PR is described

---

## 4. Tests

- [ ] New behavior has both happy path AND failure paths tested (validation errors, auth failures, edge cases)
- [ ] External HTTP/SDKs mocked — tests never hit real services
- [ ] Shared state (feature flags, global settings) mocked, never written to a shared DB — direct writes cause flaky parallel failures and are blocking
- [ ] No destructive test scaffolding forbidden by the project (e.g. `RefreshDatabase` in a hybrid-store test env)
- [ ] A passing suite is NOT sufficient — verify tests cover the right scenarios, not just that they exist
- [ ] Statistical/randomized logic tested with enough trials and a tolerance assertion, not a single sample

---

## 5. Performance

### N+1 queries
- [ ] Loops/collections accessing relations have prior eager loading (`with`/`load`/joins/dataloader)
- [ ] Field resolvers, table columns, and template loops that read `record.relation` checked
- [ ] Repository methods returning collections consumed in loops elsewhere checked
- Clear N+1 in a hot path (list views, list queries, financial loops) → non-blocking minimum; severe/high-volume → blocking

### Scheduled jobs
- [ ] New scheduled jobs avoid the project's known peak windows (check existing schedule congestion before adding); stagger with offsets, never stack on an existing slot
- [ ] `withoutOverlapping()` / single-server guards on jobs that must not run twice

### General
- [ ] No unbounded queries on large tables without `limit()` or cursor pagination
- [ ] Bulk operations chunked, not `foreach` over full collections
- [ ] Expensive computations cached with TTL and an invalidation strategy; caching never applied to financial/audit models

---

## 6. Intent Cross-Check

- Cross-reference commit messages with the diff — a "small refactor" that touches critical logic (money, auth, state machines) gets full-feature scrutiny
- Check recent history of changed files (`git log`) — spot drift from existing patterns and unfamiliar territory for the author
- If the diff doesn't explain WHY a critical change was made (no spec, no PR body, no commit rationale), flag it as a question instead of guessing
