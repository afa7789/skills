# Engineering
- Linter with per-function complexity ≤ 10 unless the project sets otherwise; per-stack config in
  `resources/stacks/{typescript,rust,python,golang,svelte,tauri}.md`. Simplify flow; never split functions to dodge it.
- Layers: transport → business → domain → data. Infra behind an interface only when a swappable provider is a stated requirement.
- Every route, command and subscriber is proven reachable through the composed app, not only by a handler test.
- Reusable-entity identity is normalized at write time (trim, case-fold, NFC) and enforced by a unique index.
- Tests assert observable behavior at boundaries; no test-only exports, no duplicate tests.
- Heavy suites (business rules, edge cases, e2e) are tagged and run on demand or when their files change.
- CI: lint → build → smoke checks. Web products set HTTP cache headers where they apply.
