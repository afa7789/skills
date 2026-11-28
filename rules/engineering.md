# Engineering
- Linter with per-function complexity ≤ 10 unless the project sets otherwise; per-stack config in
  `resources/stacks/{typescript,rust,python,golang,svelte,tauri}.md`. Simplify flow; never split functions to dodge it.
- Layers: transport → business → domain → data. Infra behind an interface only when a swappable provider is a stated requirement.
- Every route, command and subscriber is proven reachable through the composed app, not only in isolation.
- Reusable-entity identity is normalized at write time (trim, case-fold, NFC) and enforced by a unique index.
- Avoid writing tests by default; prove behavior with build, lint and smoke checks. Only add tests when the project uses them or the user asks — when written, assert observable behavior at boundaries (no test-only exports, no duplicate tests; heavy suites tagged/on-demand).
- CI: lint → build → smoke checks. Web products set HTTP cache headers where they apply.
