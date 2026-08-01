# UX / UI Review

**App:** <app> · **Stack:** <framework> · **Standard:** <material-3 | hig | fluent | custom>
**Mode:** <audit | plan | fix> · **Date:** <date> · **Commit:** <sha>
**Catalog:** `.ux-review/ui-catalog.yaml` · **Inventory:** `SCREEN_INVENTORY.md`
**Context:** <PRODUCT.md> · <DESIGN.md> · <surface brief> · **Visitor mode:** <mode>

## 1. Scope and coverage

| | |
|---|---|
| Screens reviewed | N of M in the catalog |
| States reviewed | N |
| Viewports | mobile, tablet, desktop |
| Themes | light, dark |
| Screenshots | N (`screenshots/before/`) |
| Capture failures | N (`audits/capture-failures.md`) |
| Screens not reviewed | list + reason |

## 2. Verdict

<Two or three sentences. What is the actual state of this UI, what is the single
biggest problem, and what is the highest-leverage fix. No hedging.>

| Severity | Findings | Screens affected |
|---|---|---|
| P0 — blocks use / WCAG A-AA failure | N | ... |
| P1 — significant UX problem | N | ... |
| P2 — visual / design-system inconsistency | N | ... |
| P3 — refinement | N | ... |

Dropped during consolidation: N (no evidence or no concrete fix).
Downgraded to questions: N.

## 3. Automated audit summary

| Screen | axe violations (critical/serious/moderate) | Contrast failures | Targets < min | Overflow | Reflow @320px |
|---|---|---|---|---|---|
| dashboard | 2 / 3 / 5 | 4 | 1 | mobile | fail |
| login | 0 / 1 / 2 | 1 | 0 | — | pass |

## 4. Cross-cutting problems (fix these first)

Problems that appear on many screens and close many findings with one change.

### CC-1 · <name> — closes N findings · effort <S/M/L>
**Pattern:** <what is systematically wrong>
**Screens:** <list>
**Root cause:** `<file:line>` — <the shared component / token / theme responsible>
**Fix:** <the single change>

## 5. Findings by screen

### `<screen-id>`

Shots: `before/<screen>__default__mobile.png` · `__loading__` · `__empty__` · `__error__`

#### P0 · a11y · dashboard / default / mobile
**Owner:** accessibility · **Location:** `MetricCard.tsx:34`
**What:** Secondary metric labels render at 2.8:1 contrast.
**Evidence:** `before/dashboard__default__mobile.png` (metric cards row) ·
`audits/dashboard__default.axe.json` → `color-contrast`, 4 nodes
**Why it matters:** The supporting numbers are unreadable in daylight and for
low-vision users; the primary value alone does not carry the meaning.
**Rule:** WCAG 2.2 · 1.4.3 Contrast (Minimum) — measured 2.8:1, requires 4.5:1
**Fix:** Replace the hard-coded `#8A8A8A` with `on-surface-variant` (4.7:1) in
`MetricCard.tsx:34`.
**Corroborated by:** accessibility, visual UI · **Confidence:** high
**Verification:** verified — axe and rendered-pair measurement

<repeat per finding, sorted P0 → P3>

## 6. Conflicts resolved

| # | Tension | Decision | Reason |
|---|---|---|---|
| 1 | Visual UI wants denser list rows; Accessibility wants 48dp targets | 48dp targets | Accessibility wins ties; density recovered by reducing horizontal padding |

## 7. Open questions (need interaction, code or product knowledge)

| # | Question | Why a screenshot cannot answer it | Who decides |
|---|---|---|---|
| 1 | Does the error toast get announced to a screen reader? | Requires runtime AT inspection | engineering |
| 2 | Is the admin drawer intentionally hidden from managers? | Product rule | product |

## 8. What works well

- <max 5 bullets — this tells the fixer what not to break>

## 9. Gaps in this review

- Screens that could not be captured, and why.
- States that do not exist in the code (their absence is a finding — see P1 list).
- Masked regions that were therefore not reviewed.
- Anything in `UNRESOLVED_SCREENS.md` still unresolved.

---

## 10. Results (fix mode only — appended after Phase 9)

**Fixed on branch:** `ux/<scope>-pass` · **Re-captured:** <date>

| Severity | Before | After | Fixed | Partial | Not fixed | Regressed |
|---|---|---|---|---|---|---|
| P0 | N | N | N | N | N | N |
| P1 | N | N | N | N | N | N |

| Audit metric | Before | After |
|---|---|---|
| axe violations (total) | N | N |
| Contrast failures | N | N |
| Targets below minimum | N | N |
| Screens with horizontal overflow | N | N |

### Per-finding outcome
| Finding | Outcome | Evidence |
|---|---|---|
| P0 · a11y · dashboard/default | fixed | `comparisons/dashboard__default__mobile.diff.png`, contrast now 4.7:1 |

### Regressions found
<list, or "none". Never omit this section.>

### Checks after the fixes
| Check | Result |
|---|---|
| lint | PASS / FAIL |
| type check | PASS / FAIL |
| tests | PASS / FAIL (N failing — list them) |
| re-capture determinism (two runs identical) | PASS / FAIL |
