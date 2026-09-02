---
name: better-interface
description: Holistic frontend design and review gateway that coordinates better-accessibility, better-layout, better-writing, better-typography, better-colors, better-ui, and frontend-audit. Use when shaping, building, redesigning, critiquing, improving, polishing, hardening, adapting, onboarding, optimizing, extracting a design system, or reviewing a complete screen, flow, feature, or product interface. Supports concise intent routing, persistent product/design context, quick visual verification, and escalation to full audits. Triggers on better-interface, improve the UI, improve the UX, review the UX, shape the UI, redesign the interface, polish the UI, harden the frontend, adapt the interface, onboarding UX, frontend performance, extract the design system, holistic UI review, or review the whole interface.
---

# Design the interface as one system

Use this skill as the frontend gateway. Let each `better-*` skill own its domain rules; use `frontend-audit` for exhaustive inventory and audit work. Do not duplicate their guidance here.

## Start here

1. Read [`reference/context.md`](reference/context.md). Resolve the project context before judging or editing.
2. Resolve one primary intent from the routing table. If two intents materially change the work, ask once; otherwise choose the narrower one.
3. Classify the surface by visitor success:
   - `Persuade`: decide and act; marketing, pricing, campaigns.
   - `Operate`: complete a task; apps, dashboards, settings, tools.
   - `Read`: understand; docs, articles, help, changelogs.
   - `Experience`: explore the work itself; portfolios, galleries, showcases.
4. State whether the work is a `refinement`, which preserves the incumbent identity and behavior, or a `redesign`, which preserves product truth and function but replaces the visual system.
5. Load only the playbook and domain skills needed for the request.

The user's brief wins. Project tokens, components, platform conventions, and confirmed brand commitments outrank generic taste. Treat code and rendered output as evidence even when `DESIGN.md` is absent.

## Route by intent

| Intent | Route |
| --- | --- |
| `shape` or new UI | Read [`reference/shape.md`](reference/shape.md), then load the relevant `better-*` skills |
| `build` or `redesign` | Shape only unresolved decisions, implement with the relevant domain skills, then run [`reference/quick-gate.md`](reference/quick-gate.md) |
| `critique` or holistic review | Use the review flow below; do not edit unless asked |
| `polish` | Preserve scope, inspect the rendered interface, fix the highest-leverage P1–P3 issues, then run the quick gate |
| `harden` | Read [`reference/harden.md`](reference/harden.md) |
| `onboard` | Read [`reference/onboard.md`](reference/onboard.md) |
| `adapt` | Load `better-layout`, `better-accessibility`, and `better-typography`; test real constrained sizes and input modes |
| `optimize` | Read [`reference/optimize.md`](reference/optimize.md) |
| `extract` | Read [`reference/extract.md`](reference/extract.md) |
| `audit`, every screen, or full audit | Hand off to `frontend-audit`; its inventory, artifacts, and write gates take precedence |

## Domain ownership

Load the minimum set that covers the work:

1. `better-accessibility`: semantics, keyboard, focus, forms, assistive technology.
2. `better-layout`: grouping, hierarchy, spacing, responsive behavior, RTL.
3. `better-writing`: labels, errors, empty states, voice, terminology.
4. `better-typography`: fonts, type scale, wrapping, text behavior.
5. `better-colors`: palette, contrast, gamut, semantic color tokens.
6. `better-ui`: icons, elevation, radius, motion, interaction polish.

When multiple skills cover one symptom, assign it to the owner of the root rule and mention secondary effects. Report or fix the root cause once.

## Canonical finding contract

Use this taxonomy across every frontend review, detector, QA handoff, and fix plan:

| Severity | Meaning |
| --- | --- |
| `P0` | Blocks a core task, hides content or controls, risks data loss, causes a runtime failure, or creates a WCAG A/AA barrier |
| `P1` | Significantly harms comprehension, completion, recovery, responsiveness, or trust |
| `P2` | Creates a repeated design-system, consistency, or maintainability problem |
| `P3` | Isolated refinement or contextual advisory with limited task impact |

Every finding contains: `severity`, `confidence`, `owner`, `location`, `evidence`, `user impact`, `proposed change`, and `verification status`. Prefer systemic fixes over leaf patches. A score may summarize a review, but it never replaces findings.

## Review flow

Use `quick` unless the user requests `full`.

| Mode | Coverage |
| --- | --- |
| `quick` | Primary path, changed surfaces, narrow and wide viewports; report P0–P3, ranked by impact |
| `full` | Requested scope across all six domains and implemented states; report P0–P3 |

Report every finding you can evidence, ranked by impact; in `quick` mode lead with the changes that matter on the primary path.

1. Inspect framework, styling system, tokens, components, viewports, preview commands, and relevant context artifacts.
2. Inspect rendered output for visual claims. Mark anything not observed as `Not verified`. Confirm the surface rendered real content rather than the layout shell; when routes, links, nav entries or icons are in scope, run `check-wiring.mjs` from `frontend-audit` and treat its `error` findings as P0.
3. Walk the implemented loading, empty, error, disabled, permission, and success states in scope.
4. Consolidate by root cause and rank by severity, reach, and leverage.
5. Record 1–3 plausible changes rejected because the evidence, brief, or project system does not support them.
6. Treat review requests as read-only. Edit only when the user requests implementation.

### Review output

State scope, intent, visitor mode, refinement/redesign boundary, evidence inspected, and gaps. Then use:

| # | Severity | Confidence | Owner | Location | Evidence and impact | Proposed change | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

Verdict:

- `Block`: unresolved P0.
- `Needs changes`: unresolved P1–P3.
- `Approve`: no actionable findings and claimed coverage was verified.

## Heuristics and restraint

Classify checks before enforcing them:

- `error`: objective breakage; always actionable.
- `warning`: likely user or system harm; require evidence.
- `advisory`: aesthetic saturation or generated-UI tell; apply only when the brief and context agree.

Never turn popular fonts, palettes, gradients, card layouts, or stylistic trends into universal bans. Honor explicit design direction and document intentional exceptions. Prefer one bounded inspection-and-fix pass plus one confirmation over open-ended polishing.

## Common mistakes

| Mistake | Correction |
| --- | --- |
| Six disconnected domain reports | Consolidate into one root-cause list |
| Designing before resolving product and surface context | Read the context contract first |
| Applying marketing expressiveness to an operational tool | Classify visitor success per surface |
| Treating an advisory as a defect | Require contextual evidence and allow explicit exceptions |
| Visual judgment from source alone | Inspect the rendered state or mark it unverified |
| Approving a screen that rendered only header, footer and background | Assert content in the main region before judging anything visual |
| Treating an unreachable screen as a visual problem | Reachability is a P0 owned by the wiring check, not a polish item |
| Full audit for a small UI diff | Use the quick gate |
| Unlimited visual iteration | One correction batch and one confirmation |
| Review silently edits code | Keep review read-only unless implementation was requested |
