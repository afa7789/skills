# Static source checks — wiring and detector

Two deterministic scripts, one shared contract. Both read source files with no
execution, both are invoked as `node <skill>/scripts/<script>.mjs --json <target>`,
both exit `0` clean, `1` when at least one `error`-class finding exists, `2` when
the tool itself failed (including an invalid target). Both share one ignore-config
format — copy [`../assets/ui-quality.example.json`](../assets/ui-quality.example.json)
to `.ui-quality.json` only when the project needs exceptions:

- `ignoreRules`: suppress a rule globally; avoid this for `error` rules.
- `ignoreFiles`: glob patterns for generated or legacy surfaces.
- `ignores`: narrow by `rule`, `file`, and/or exact evidence text.

A finding is evidence to inspect, not permission to override a confirmed brief —
the product/design context and the owning `better-*` skill decide whether a
`warning` or `advisory` becomes a reportable finding.

---

## `check-wiring.mjs` — routes, handlers, and the icon registry

A screen inventory derived from the router can only see what the router declares.
The failures it structurally cannot see are the expensive ones: a link to a route
that was never registered, a handler that exists but is not mounted, a catch-all
that does not exist so an unknown URL renders the layout shell, an icon class
that is not in the bundle. Component tests pass, the screenshot looks clean, and
the defect ships.

This check closes the loop in the other direction: it reconciles **what the code
references** against **what the app registers**.

```bash
node <skill>/scripts/check-wiring.mjs --json src
node <skill>/scripts/check-wiring.mjs --config .ui-quality.json .
```

### Rules

| Rule | Class | Sev | Catches |
|---|---|---|---|
| `broken-link` | error | P0 | An `href`/`to`/`router.push`/`navigate`/`goto`/`redirect` target that matches no declared route. A catch-all never counts as a match — resolving to the not-found view *is* the defect. |
| `missing-catch-all` | error | P0 | A router with 3+ routes and no catch-all, so a wrong URL renders header, footer and background with no content. |
| `unregistered-handler` | error | P0 | A handler/controller/endpoint module that exports something and that no other module imports — built, tested in isolation, never mounted on the app. |
| `unregistered-icon` | warning | P1 | An `fa-*` class used in markup whose icon is absent from the imported registry (`library.add`, `faXyz` imports, `icon=` props). |
| `orphan-route` | warning | P2 | A declared route that product code never links to and never navigates to by name. Dead route, or a missing entry point. |
| `route-literal` | warning | P2 | Literal path strings at call sites while the router declares named routes. Reported once per file with a count. |

### What it reads

- **Declared routes** — object route tables (`path:` inside a file that also
  contains a router marker), JSX `<Route path>`, `createFileRoute`, and
  file-based conventions (`src/routes/**/+page.*`, `app/**/page.*`,
  `pages/**/*`). Route groups `(marketing)` are stripped, `[id]`/`[...slug]`
  become params, `api/`, `_app`, `+layout`, `+server` are excluded.
- **Route names** — paired to a path by proximity inside the same route entry, so
  navigation by `{ name: 'dashboard' }` counts as reaching the route.
- **Server registrations** — `app.get('/x')`, `router.use('/api', …)` and friends.
  Used to prove a handler module is mounted and to keep API paths out of the
  frontend link space; **not** used as a frontend route table, because mounted
  sub-routers make prefix composition unreliable from grep alone.

### Deliberate trade-offs

- **Test files count as referencing code for `broken-link`.** A test that drives
  `/__dev/screens/x` against a router that no longer registers it is the exact
  bug this rule exists for. They do **not** count for `orphan-route` — a route
  only a test reaches has no product entry point.
- **Confidence drops to `medium` when the route table has relative (nested) child
  paths**, because full paths compose across parents and grep cannot follow the
  composition. Read the router before acting on those.
- **Rules self-disable rather than guess.** No route table found → no route rules.
  An autoloader (`import.meta.glob`, `require.context`, `@fastify/autoload`,
  `readdirSync`) → no `unregistered-handler`. A full Font Awesome stylesheet
  imported → no `unregistered-icon`. Silence here is a coverage gap, not a pass:
  say so in the report.
- Repos with route fixtures inside test data will produce `broken-link` noise.
  Scope it with `ignoreFiles: ["**/fixtures/**"]` — never by dropping the rule.

### Reporting

Write the raw output to `.ux-review/audits/wiring.json`. Every `error` is a P0 in
`UX_REVIEW.md` regardless of how the screen looks: the screenshot of a shell-only
page is evidence of the symptom, not a defence against the finding. Pair each
`broken-link` with the entry point a user would click, so the fix plan names a
route to register or a link to correct rather than "fix navigation".

---

## `detect-ui.mjs` — deterministic frontend detector

The detector scans HTML, CSS, JavaScript/TypeScript (including JSX, modules, and
MDX), Vue, Svelte, and Astro sources. It skips dependencies, generated output,
captures, and build directories. It judges each file **on its own**, so it cannot
see cross-file wiring — that gap is exactly what `check-wiring.mjs` above covers.

```bash
node <skill>/scripts/detect-ui.mjs --json src
node <skill>/scripts/detect-ui.mjs --config .ui-quality.json src/app.tsx
```

### Rule classes

- `error`: objective access or runtime breakage; inspect as P0.
- `warning`: probable user or system harm; assign P1 or P2 from impact and reach.
- `advisory`: contextual design heuristic; at most P3 and never enforce against a confirmed brief.

The initial registry covers disabled zoom, positive tabindex, non-semantic click
targets, missing image alternatives, focusable `aria-hidden` elements, autoplay
without controls, empty link targets, missing button types, removed focus
outlines, raw HTML sinks, transition-all, tiny text, skipped heading levels,
nested cards, gradient text, directional CSS, and decorative pulse.
