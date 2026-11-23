# Ponytail + Wiring Lens

Flag code that should not exist, and code nobody can reach. One line per finding:
`<file>:<line> <tag>: <what>. <replacement>.` The replacement is concrete: name the helper, function or feature, or show the shorter form.

## Ponytail — code that should not exist

| Tag | Catches |
|---|---|
| `delete:` | Dead code, unused flexibility, speculative feature. Nothing replaces it. |
| `reuse:` | Re-implements a helper, util, type or pattern already in this repo. Name it. |
| `stdlib:` | Hand-rolled thing the standard library ships. Name the function. |
| `native:` | Code or dependency doing what the platform already does. Name the feature. |
| `dep:` | New package for what existing deps or a one-liner cover. |
| `yagni:` | Abstraction with one implementation, config nobody sets, layer with one caller. |
| `wrapper:` | Only forwards to another call. Keeps its layer only if it owns a policy (retry budget, error mapping, default, security check). An effect alone (log line, rethrowing try/catch, null check on validated input) does not count. Call the target directly. |
| `types:` | Type bloat or invented type (below). |
| `one-caller:` | Helper with exactly one call site. Inline it, or name the second caller. "One caller + one future caller" is one caller. |
| `shrink:` | Same logic, fewer lines. Show the shorter form. |

`types:` — typing is required, inventing types is not. Flag:
- Hand-written shape where the library, SDK or schema exports one. Name the export.
- Union or optional that encodes the author's uncertainty (`string | number` because nobody checked). Ask which it is.
- Checker switched off at the least certain point: `as X`, `!`, `any`, `Dict[str, Any]`, `# type: ignore`.
- Ceremony: newtype for one call site, generic with one instantiation, interface with one implementer, alias restating a builtin, annotation the checker infers.
- Return type that shifts between branches; `Promise<any>` / `Result<any>` masking a missing schema.

A **missing** annotation is never ponytail. It is a correctness gap in the other direction.

## Wiring — code nobody can reach

| Tag | Catches |
|---|---|
| `wiring:` | New route, handler, command or subscriber not registered at the composition root, or tested only as a handler, not through the composed app. |
| `orphan:` | Reference to a path, route name, icon or asset that does not resolve, in code, tests, seeds or docs. |
| `route-literal:` | Literal URL where the project has route names or a routes module. |
| `dup-entry:` | Same user action offered from a third surface with no single owner. |
| `identity:` | Reusable-entity uniqueness enforced only in app code, or compared without normalization (trim, case, whitespace, Unicode NFC). No unique index on the normalized value. |

Diff renames, moves or deletes a route, handler or asset id → grep the old name across source, tests, seeds and docs. Any survivor is `orphan:`, green build or not.

## Rules

- **Blocking by default.** Every finding blocks, `delete:` included (removal is its replacement). Demote to `(nit)` only when it saves < 3 lines with no clarity gain. `wiring:`, `orphan:` and `route-literal:` never demote.
- **`ponytail:` marker.** A comment `ponytail: <ceiling>, <upgrade trigger>` marks a deliberate simplification. It is intent, not a defect: check only that the ceiling and trigger are reasonable. A marker with no upgrade trigger is a finding, `no-trigger:`. It rots into permanence.
- **Do not over-apply.** Never flag input validation at trust boundaries, error handling, security, accessibility, required type annotations, architecture the user or spec explicitly asked for, or required tests. Less code is the goal; less safety is not. Correctness, security and performance belong to the other review steps, not this lens.
- **Metric.** End with `net: -<N> lines possible`, the lines the findings remove. Nothing to cut: `net: Lean already.`
