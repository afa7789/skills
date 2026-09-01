<!-- canonical twin: agents/code-reviewer.md — keep both in sync -->

# Ponytail Lens + Wiring Lens

## Ponytail Lens -- Flag the Code That Shouldn't Exist

The best code is the code never written. Beyond correctness, review every diff for code that fails the lazy-senior-dev ladder -- these are **Maintainability** (and sometimes **Completeness**) findings:

Report each finding as one line: `<file>:L<line>: <tag> <what>. <replacement>.` Tags:

| Tag | What it catches |
|---|---|
| `delete:` | Dead code, unused flexibility, speculative feature. Nothing replaces it. |
| `reuse:` | Re-implements a helper, util, type, or pattern that already exists in this repo. Name the existing one. |
| `stdlib:` | Hand-rolled thing the standard library ships. Name the function. |
| `native:` | Dependency or code doing what the platform already does. Name the feature. |
| `dep:` | New package added for what existing deps or a one-liner cover. |
| `yagni:` | Abstraction with one implementation, config nobody sets, layer with one caller. |
| `wrapper:` | Function/class/module that only forwards to another, adding no validation, error translation, default, or 2+-caller seam. Call the thing directly. Also flag cosmetic wrappers -- one-line passthroughs that add logging, a trivial retry, or validation the caller already does. The test: does the wrapper own a *policy* (retry budget, error mapping, default value, security check), or only an *effect* (log line, try/catch with rethrow, null check on an already-validated input)? Effects don't justify a layer. |
| `types:` | See below. |
| `one-caller:` | Helper / private method / utility function with exactly one call site in the diff or repo. Inline it, or name the second caller. "One caller + one future caller" is not a caller. |

## Wiring Lens -- Flag the Code Nobody Can Reach

A diff that adds a route, handler, command or asset without registering it passes
every unit test and ships broken. These are **Completeness** findings, and the
first three are blocking:

| Tag | What it catches |
|---|---|
| `wiring:` | New route / handler / command / event subscriber with no registration at the composition root, or a test that covers the handler but not the registration. |
| `orphan:` | Reference to a path, route name, icon or asset that does not resolve — including in tests, seeds and docs. |
| `route-literal:` | Literal URL string where the project has route names or a canonical routes module. |
| `dup-entry:` | The same user action offered from a third surface with no single owner. |
| `identity:` | Reusable-entity uniqueness enforced only in application code, or compared without normalization (case, whitespace, Unicode form). |

For any diff that renames, moves or deletes a route, handler or asset id, grep the
old name across `src`, tests, seeds and docs before approving. A surviving
reference is a `orphan:` finding even when the build is green.

When `frontend-audit` is available, run it instead of eyeballing:
`node <frontend-audit>/scripts/check-wiring.mjs --json .`

| `shrink:` | Same logic, fewer lines. Show the shorter form. |

**`types:` findings** -- typing is required, inventing types is not. Flag:
- A hand-written shape where the library, SDK, or schema already exports the type. Name the export that should have been used.
- A union or optional that encodes the author's uncertainty rather than the real contract (`string | number` because nobody checked which). Ask which it actually is.
- Gratuitous assertions that switch the checker off at the least certain point: `as X`, `as const`, `!`, `any`, `ref<any>`, `Dict[str, Any]`, `# type: ignore`.
- Type ceremony: newtype for one call site, generic with one instantiation, interface/`Protocol` with one implementer, alias restating a builtin, annotation the checker already infers.
- Semantically wrong types that the *user's own code* invented, not the library: return type that shifts between branches (e.g. `T | undefined | null` in some paths, bare `T` in others); `Promise<any>` / `Result<any>` masking a missing schema; generic with `any` as the output parameter; type that encodes the *author's hesitation* instead of the contract (`string | number` because nobody read the docs -- pick one and justify).

Never flag a **missing** annotation as ponytail bloat -- required types are correctness, and their absence is a `Maintainability` defect in the other direction.

A deliberate simplification marked with a `ponytail:` comment is intent, not a defect -- do not flag it; verify the named ceiling/upgrade path is reasonable. A `ponytail:` marker with no upgrade path IS a finding (`no-trigger`): it rots into permanence.

End the lens with the only metric it owns: `net: -<N> lines possible.` Nothing to cut: `Lean already.`

**Ponytail/Wiring findings are blocking by default** — a `delete:`, `reuse:`, `stdlib:`, `dep:`, `yagni:`, `wrapper:`, or `one-caller:` finding with a named replacement is its own blocking issue, not an input averaged into the Maintainability score. Catching bloat here costs one review comment; shipping it costs a rebuild later. Only demote to a suggestion when the replacement is genuinely marginal (saves <3 lines, no clarity gain).

**Do not over-apply:** never penalize input validation at trust boundaries, error handling, security, accessibility, required type annotations, explicitly-requested architecture (see [Scope & precedence](../../rules/engineering.md#scope--precedence)), or required tests. Less code is the goal; less safety is not. Correctness bugs, security holes, and performance are graded by the criteria above, not by this lens.
