---
name: frontend-ux-loop
description: Cross-platform UI/UX audit and improvement loop. Discovers every screen and visual state first (routers, file-based routes, navigators, previews, tests), builds a normalized ui-catalog, sets up a catalog/harness (Storybook, Widgetbook, native previews), captures deterministic screenshots (Playwright for web, Maestro for mobile), runs automated a11y/layout audits, dispatches a real parallel panel of UX/UI/Material-3/a11y reviewer subagents, then reports, fixes and re-captures for before/after comparison. Works for React, Vue, Svelte, Angular, Next, Nuxt, SvelteKit, React Native, Expo, Flutter, Android/Compose and iOS/SwiftUI. Trigger with "ux loop", "audit the UI", "screenshot every screen", "review the UX", "improve the UX", "/frontend-ux-loop".
---

# Frontend UX Loop — inventory → capture → panel review → fix → compare

One pipeline for every frontend. The **flow is generic**; only three steps are
platform-specific (discovery, harness, capture). Everything downstream — the
catalog, the audits, the review panel, the report, the diff — is shared.

> **Trigger phrases:** "ux loop", "audit the UI", "audit the UX", "screenshot every screen",
> "review the UX", "improve the UX", "material design review", "a11y review of the app",
> "/frontend-ux-loop", "/ux-loop"

Throughout this file, `<skill>` means the directory holding this SKILL.md
(e.g. `~/.claude/skills/frontend-ux-loop`). Load a reference only when its phase
runs — never all of them up front.

```
Phase 1  detect stack ──────────────────────► reference/discovery.md
Phase 2  DISCOVER SCREENS + STATES ─────────► scripts/discover-screens.sh
Phase 3  ui-catalog.yaml (user confirms) ───► assets/ui-catalog.example.yaml
Phase 4  harness + determinism ─────────────► reference/web.md | reference/mobile.md
Phase 5  capture screenshots ───────────────► reference/capture.md
Phase 6  automated audits ──────────────────► reference/accessibility.md
Phase 7  UX/UI/M3/a11y panel (real agents) ─► reference/review-rubric.md
Phase 8  UX_REVIEW.md + FIX_PLAN.md
Phase 9  fix → re-capture → before/after
```

---

## ⚠️ Hard requirements

1. **Screens are discovered before anything is configured or captured.** Never
   guess a route list, never audit "the pages I happen to know". Phase 2 is not
   optional and it must be evidence-backed (`file:line` for every screen).
2. **Never claim the inventory is complete.** Report coverage *and* gaps
   (`UNRESOLVED_SCREENS.md`). A screen behind a feature flag, a role guard or a
   dynamic route is a gap, not a silent omission.
3. **The review panel runs as real parallel `Agent` calls** — not role-play in the
   main thread. If the `Agent` tool is unavailable, STOP and say so.
4. **Nothing is captured non-deterministically.** No live clock, no live network,
   no unseeded random data, no running animations. Otherwise every re-capture is
   a false diff.
5. **Mode gates writes** (see Phase 0). `audit` never edits product code.

---

## Phase 0 — Mode, scope, safety

Resolve the mode from the user's phrasing. Default is `audit`.

| Mode | Does | Touches product code |
|------|------|----------------------|
| `audit` | inventory + capture + audits + panel + report | no |
| `plan` | `audit` + `FIX_PLAN.md` with concrete diffs described | no |
| `fix` | `plan` + implements P0/P1, re-captures, compares | yes |

Then:

1. `rtk git status` — if dirty, say so and ask before continuing.
2. For `fix` mode, branch first: `rtk git checkout -b ux/<scope>-pass`.
3. Create the output directory. **Everything this skill writes lives here:**

```
.ux-review/
├── ui-catalog.yaml            # the normalized manifest (source of truth)
├── SCREEN_INVENTORY.md        # what was found, with evidence + confidence
├── UNRESOLVED_SCREENS.md      # gaps, guarded routes, unknown params
├── screenshots/
│   ├── before/<screen>__<state>__<viewport>.png
│   └── after/<screen>__<state>__<viewport>.png
├── audits/                    # axe / contrast / overflow / target-size JSON
├── comparisons/               # before-vs-after diffs
├── UX_REVIEW.md               # consolidated panel findings
└── FIX_PLAN.md                # prioritized, actionable
```

4. Add `.ux-review/` to `.gitignore` unless the user wants the report committed
   (screenshots are large; ask).

---

## Phase 1 — Detect the stack

Run the detector; it prints the platform, package manager, router, existing
catalog and existing capture tooling:

```bash
bash <skill>/scripts/discover-screens.sh --detect-only
```

It reads `package.json`, `pubspec.yaml`, `*.xcodeproj`/`Package.swift`,
`build.gradle{,.kts}`, `app.json`/`app.config.*`, and lockfiles.

State the detected stack to the user before proceeding. If the repo is a
monorepo, ask which app(s) to audit — do not audit all of them by default.

Then load **only** the adapter you need:
- Web (React / Vue / Svelte / Angular / Next / Nuxt / SvelteKit / Astro) → [`reference/web.md`](reference/web.md)
- Mobile & native (React Native / Expo / Flutter / Compose / SwiftUI) → [`reference/mobile.md`](reference/mobile.md)

---

## Phase 2 — Discover screens and states (mandatory, first)

```bash
bash <skill>/scripts/discover-screens.sh --out .ux-review
```

The script greps every route/navigation/preview/test source listed in
[`reference/discovery.md`](reference/discovery.md) and emits candidates with
evidence. **Read that reference before interpreting the output** — it explains
each pattern, its false positives, and what the script cannot see.

Then do the part a grep cannot: read the router files and screen components the
script pointed at, and derive for each screen:

- **route** and **parameters** (with a realistic sample value per param)
- **auth role / guard** required to reach it
- **visual states actually implemented in the code**, not imagined ones —
  look for `isLoading`, `error`, `data.length === 0`, `disabled`, `AsyncValue`,
  `Suspense`, skeletons, permission branches, offline handling
- **confidence**: `high` (explicit route entry), `medium` (inferred from
  component naming or navigator), `low` (mentioned only in a test/comment)

Write `SCREEN_INVENTORY.md` (template:
[`assets/SCREEN_INVENTORY.template.md`](assets/SCREEN_INVENTORY.template.md)) and
`UNRESOLVED_SCREENS.md` (anything you could not resolve, and *why*: dynamic
segment with unknown id, screen behind a flag, deep link only, native-only,
dead code suspicion).

Show the user the counts — `N screens, M states, K unresolved` — before Phase 3.

---

## Phase 3 — The catalog manifest

`ui-catalog.yaml` is the only platform-agnostic contract in the pipeline; every
later phase reads it and nothing else. Generate it from the inventory, then
**ask the user to confirm or correct it** — this is the cheapest possible moment
to catch a missing screen.

Schema and a filled example: [`assets/ui-catalog.example.yaml`](assets/ui-catalog.example.yaml).

```yaml
standard: material-3          # material-3 | hig | fluent | custom:<path-to-tokens>
platform: web                 # web | react-native | flutter | android | ios
viewports:                    # web/RN; devices: for native
  - { name: mobile,  width: 390,  height: 844,  dpr: 3 }
  - { name: desktop, width: 1440, height: 1000, dpr: 2 }
screens:
  - id: dashboard
    route: /dashboard
    component: DashboardPage
    role: user
    confidence: high
    evidence: [src/router/index.ts:82]
    states: [default, loading, empty, error]
```

If the user adds a screen the discovery missed, record it in
`UNRESOLVED_SCREENS.md` as a **discovery miss** with the pattern that should
have caught it. That is the feedback loop that makes the next run better.

---

## Phase 4 — Harness and determinism

Pick the catalog mechanism for the platform (details in the adapter reference):

| Platform | Catalog / harness | Data mocking |
|---|---|---|
| React / Vue / Svelte / Angular / web components | **Storybook** (one story per screen×state) | `msw-storybook-addon` |
| Next / Nuxt / SvelteKit / Astro | Storybook for screens + the real dev server for routes | MSW + fixture loaders |
| React Native / Expo | Storybook for React Native (on-device) or a screen harness | DI / fake services |
| Flutter | **Widgetbook** use-cases | fake repositories |
| Android Compose | `@Preview` + Compose screenshot tests | fake repositories |
| iOS SwiftUI | `#Preview` variants | fake repositories |

**Never rebuild what exists.** If the project already has Storybook, Widgetbook
or previews, extend them; adding a parallel harness is a maintenance bomb.

**Determinism checklist — every item, every platform** (recipes in
[`reference/capture.md`](reference/capture.md)):

- [ ] Network intercepted with fixtures — zero real requests
- [ ] Clock frozen to a fixed timestamp; fixed timezone and locale
- [ ] Seeded/static data — no `Math.random()`, no `faker` without a seed
- [ ] Animations and transitions disabled; caret/blink hidden
- [ ] Fonts loaded and awaited before the shot
- [ ] Fixed viewport, DPI and color scheme (capture light **and** dark if the app has both)
- [ ] Scroll position reset; lazy content forced to load

In `audit` mode, harness/mock files are **new** files (`*.stories.*`,
`*.widgetbook.dart`, `.ux-review/harness/**`). Do not modify product code to
make capture easier — if capture is impossible without a product change, that is
itself a finding (untestable UI).

---

## Phase 5 — Capture

[`reference/capture.md`](reference/capture.md) holds the shared contract — the shot
matrix, the fixed naming, determinism, masking and the comparison rules. The
runnable per-platform recipes are in the adapter you loaded in Phase 1.

- **Web** — Playwright drives either the built Storybook (enumerate stories from
  `index.json`, screenshot the canvas) or the real dev server routes (for auth
  flows, real layout, real scroll). Prefer Storybook for states, real routes for
  end-to-end truth; do both when they disagree, because the disagreement is a
  finding.
- **Mobile/native** — Maestro drives the built app on emulator/simulator via the
  accessibility tree (`takeScreenshot`), which works for RN, Flutter, Compose and
  SwiftUI alike. On-device Storybook/Widgetbook gives state isolation; Maestro
  gives real-device truth.

Naming is fixed — the comparison step depends on it:
`screenshots/before/<screen-id>__<state>__<viewport>[__dark].png`

Log every capture failure into `audits/capture-failures.md` with the reason.
A screen that cannot be captured must never disappear silently from the report.

---

## Phase 6 — Automated audits (before the humans-in-a-box)

Machines first: they find the objective violations cheaply so the panel spends
its attention on judgment. Details and thresholds in
[`reference/accessibility.md`](reference/accessibility.md).

Per screen×state, collect into `audits/`:

1. **a11y** — axe-core (Storybook a11y addon, `@axe-core/playwright`, or
   Accessibility Scanner / Espresso / XCUITest on native).
2. **Contrast** — text and non-text contrast ratios against WCAG 2.2 (4.5:1 body,
   3:1 large text and UI components).
3. **Touch targets** — minimum interactive size (M3: 48×48dp; WCAG 2.5.8: 24×24 CSS px).
4. **Overflow / truncation** — horizontal scroll on the page body, clipped text,
   layout breakage at the narrowest viewport, and at 200% zoom / largest font scale.
5. **Focus order and visible focus** — keyboard traversal on web; focus/next on native.
6. **Design-token drift** — spacing/type/color values used in the code that are
   not in the design system's scale ([`reference/material-3.md`](reference/material-3.md)).

---

## Phase 7 — The UX/UI review panel (REAL parallel agents)

Spawn the reviewers **in a single message, in parallel**, one `Agent` call each.
Each reviewer gets: the screenshots for its assigned screens (as image reads),
the relevant `audits/*` output, the `ui-catalog.yaml` entry, and the design
standard. Full prompts, roles and the finding contract:
[`reference/review-rubric.md`](reference/review-rubric.md).

| Reviewer | `subagent_type` | Owns |
|---|---|---|
| UX flow | `UX Architect` | task flow, hierarchy, cognitive load, feedback, error recovery |
| Visual UI | `UI Designer` | grid, spacing, type scale, color, density, consistency |
| Design system | `UI Designer` | component/state fidelity to Material 3 (or HIG/Fluent) |
| Accessibility | `Accessibility Auditor` | WCAG 2.2, contrast, focus, semantics, screen-reader model |
| Responsive/adaptive | `Frontend Developer` | breakpoints, overflow, orientation, font scaling, safe areas |
| Content & product | `Product Manager` | labels, empty states, microcopy, action clarity |

Rules that keep the panel honest:

- **No reviewer sees another's findings.** Independence is the whole point.
- Every finding must cite **evidence** — the screenshot filename and the region,
  or the audit entry. A finding with no evidence is dropped in Phase 8.
- Every finding must carry a **concrete proposed change**, not "improve spacing".
- Reviewers do **not** edit code.
- Batch screens (~4–8 per agent) when the catalog is large; keep each screen's
  full state set in one batch so a reviewer can judge loading→empty→error coherence.

Severity is fixed:

| | Meaning |
|---|---|
| **P0** | Blocks use, or an accessibility barrier (WCAG A/AA failure) |
| **P1** | Significant UX problem — confusion, dead end, missing feedback |
| **P2** | Visual inconsistency / design-system violation |
| **P3** | Refinement, polish |

---

## Phase 8 — Consolidate

Main thread merges the panel output into `UX_REVIEW.md` and `FIX_PLAN.md`
(templates: [`assets/UX_REVIEW.template.md`](assets/UX_REVIEW.template.md),
[`assets/FIX_PLAN.template.md`](assets/FIX_PLAN.template.md)).

Consolidation is real work, not concatenation:

1. **Deduplicate** — the same defect reported by three reviewers is one finding
   with three corroborations (raise confidence, keep the highest severity).
2. **Resolve conflicts by name** — when the UI reviewer wants density and the a11y
   reviewer wants larger targets, state the tension and decide, with the reason.
   Accessibility wins ties by default.
3. **Drop unevidenced findings** and say how many were dropped.
4. **Group by fix**, not by screen — one token change often closes twelve findings.
5. **Estimate effort** per fix and mark the ones that need a design decision
   rather than an implementation.

---

## Phase 9 — Fix, re-capture, compare (`fix` mode only)

1. Fix **P0 first, then P1**. Do not touch P2/P3 unless the user asks — scope
   creep destroys the before/after signal.
2. Prefer fixing at the **system level** (tokens, theme, shared component) over
   patching a screen. Note when you did the opposite and why.
3. Run the project's existing checks after each group: `rtk lint`, type check,
   tests. A UX fix that breaks a test is not a fix.
4. Re-capture into `screenshots/after/` with **the identical harness, seed,
   viewport and clock**. Any harness change invalidates the comparison.
5. Diff `before/` vs `after/` into `comparisons/`, and re-run Phase 6 audits.
   Report per finding: `fixed` / `partially fixed` / `not fixed` / `regressed`.
6. Append a **Results** section to `UX_REVIEW.md`: counts by severity before and
   after, audit deltas, and every regression found. Report failures plainly.

Optionally re-run one panel reviewer on the `after/` shots to confirm the fix
reads as an improvement to a fresh pair of eyes.

---

## Invocation examples

```
/frontend-ux-loop                                  # audit mode, whole app
ux loop: just discover the screens                 # stop after Phase 3
audit the UI against Material Design 3             # sets standard: material-3
review the UX of the checkout flow only            # scoped catalog
ux loop in plan mode, mobile viewport only
ux loop in fix mode, P0 and P1 only
compare before and after                           # Phase 9 only, existing catalog
```

---

## Anti-patterns

- ❌ Capturing screenshots before the screen inventory exists.
- ❌ Presenting an inventory as complete without `UNRESOLVED_SCREENS.md`.
- ❌ Role-playing the six reviewers in the main thread instead of spawning agents.
- ❌ Installing Playwright/Storybook/Maestro when the project already has an
  equivalent, or installing anything in `audit` mode without asking.
- ❌ Screenshots with live time, live network or running animations — every
  re-run then shows fake diffs.
- ❌ Findings without a screenshot reference, or with vague remedies.
- ❌ Auditing only the happy path. Loading, empty, error and permission-denied
  states are where UX actually fails.
- ❌ Only one viewport, only light mode, only the default font scale.
- ❌ Editing product code in `audit`/`plan` mode.
- ❌ Fixing P2/P3 in the same pass as P0/P1 and losing the before/after signal.
- ❌ Claiming "UX improved" without a re-capture and a re-run of the audits.
