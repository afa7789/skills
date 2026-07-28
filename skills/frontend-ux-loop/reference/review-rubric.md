# Review panel — roles, prompts, finding contract, consolidation

The panel exists to produce **evidence-backed, actionable findings**, not opinions.
Six independent reviewers, spawned as real parallel `Agent` calls, each judging
the same screenshots from a different mandate.

---

## 1. Panel composition

| # | Reviewer | `subagent_type` | Mandate |
|---|---|---|---|
| 1 | UX flow | `UX Architect` | Can the user accomplish the task? Hierarchy, cognitive load, feedback, error recovery, dead ends |
| 2 | Visual UI | `UI Designer` | Grid, alignment, spacing rhythm, type scale, color use, density, visual consistency across screens |
| 3 | Design system | `UI Designer` | Fidelity to the declared standard (Material 3 / HIG / Fluent / project tokens); component and state correctness |
| 4 | Accessibility | `Accessibility Auditor` | WCAG 2.2 AA, contrast, focus, semantics, screen-reader model, scaling |
| 5 | Responsive / adaptive | `Frontend Developer` | Breakpoints, overflow, truncation, orientation, safe areas, font scaling, keyboard overlap |
| 6 | Content & product | `Product Manager` | Labels, microcopy, empty states, action clarity, expectation setting |

Scale the panel to the job: 3 reviewers (UX, a11y, design system) for a quick
pass; all 6 for a full audit. Never fewer than UX + accessibility.

For a large catalog, batch screens (~4–8 per agent) and spawn one agent per role
per batch. **Keep all states of a screen in the same batch** — a reviewer must see
default→loading→empty→error together to judge whether they are coherent.

---

## 2. What every reviewer receives

1. The **screenshot paths** for its batch — the agent reads the PNGs directly with
   the Read tool (it renders images). List them explicitly, grouped by screen.
2. The **catalog entries** for those screens (route, role, states, viewports).
3. The relevant **audit output** (`audits/<screen>__<state>.axe.json`, contrast,
   overflow, target-size results) — so reviewers build on machine findings instead
   of re-deriving them.
4. The **declared standard** and, if it exists, the project's token file.
5. The **finding contract** (§4) — verbatim.

Reviewers get read access to the code so they can point at the exact line to
change, but they **must not edit anything**.

---

## 3. Per-reviewer prompt template

```
You are the {ROLE} reviewer on an independent UI/UX audit panel. Five other
reviewers are auditing the same screens from different mandates; you cannot see
their work and must not speculate about it. Judge only what your mandate covers —
another reviewer owns everything else.

YOUR MANDATE:
{MANDATE_BLOCK}          # from §5 below, verbatim

PRODUCT CONTEXT:
{one paragraph: what the product is, who uses it, the primary task per screen}

DESIGN STANDARD: {material-3 | hig | fluent | project tokens at <path>}
Read <skill>/reference/{material-3.md | accessibility.md} before judging, and cite
its rules by name and number.

SCREENS IN YOUR BATCH:
{for each screen: id, route, role, and the screenshot path per state × viewport}

MACHINE AUDIT OUTPUT (already collected — build on it, do not repeat it):
{paths to the audits/*.json for these screens, plus a 1-line summary each}

METHOD:
1. Read every screenshot listed. A screen you did not open cannot be reported on.
2. Compare states of the same screen against each other, and the same screen
   across viewports.
3. Compare screens against each other for consistency.
4. For each problem, write one finding in the exact format below.

FINDING FORMAT (mandatory, one block per finding):
### {P0|P1|P2|P3} · {category} · {screen-id} / {state} / {viewport}
**What:** one sentence naming the defect.
**Evidence:** {screenshot filename} — {where in the image: region, component, text}
  (+ audit entry, if any)
**Why it matters:** the concrete user consequence. No abstractions.
**Rule:** the standard/SC violated, with its number, when one applies.
**Fix:** the specific change — property, token, value, component, or copy.
  Name the file:line when you can find it in the code.
**Confidence:** high | medium (medium = might be a screenshot artifact)

SEVERITY (use exactly these):
P0 blocks use, or is a WCAG A/AA failure
P1 significant UX problem: confusion, dead end, missing feedback, lost work
P2 visual inconsistency or design-system violation
P3 refinement / polish

HARD RULES:
- No finding without a screenshot reference. Unevidenced findings are discarded.
- No finding without a concrete fix. "Improve spacing" is not a fix; "use 16dp
  gutters (spacing.4) instead of 11px" is.
- Do not invent content you cannot see, and do not assume behaviour a static
  image cannot show — if you suspect a behavioural problem, mark it as a
  QUESTION at the end instead of a finding.
- Do not edit any file.
- Report what is genuinely good in one short section at the end (max 5 bullets) —
  it tells the fixer what not to break.

OUTPUT ORDER:
## FINDINGS        (sorted P0 → P3)
## QUESTIONS       (things needing interaction, code or product knowledge to confirm)
## WORKS WELL      (max 5 bullets)
## COVERAGE        (screens×states you actually reviewed; anything you could not open)
```

Spawn rules: all agents **in one message**, one `Agent` call each, `description`
like `"UX panel: a11y reviewer, batch 2"`. If an agent returns malformed output or
fails, re-spawn that one; never fill its gap inline.

---

## 4. The finding contract (also enforced during consolidation)

A finding survives consolidation only if it has: a severity, a screen/state/viewport
anchor, a screenshot reference, a user consequence, and a concrete fix. Drop the
rest and report how many were dropped and why.

Categories (keep the vocabulary fixed so the report is groupable):
`a11y` · `contrast` · `layout` · `spacing` · `typography` · `color` · `hierarchy` ·
`feedback` · `state-coverage` · `consistency` · `design-system` · `responsive` ·
`content` · `navigation` · `performance-perceived`.

---

## 5. Mandate blocks (paste verbatim into each prompt)

**UX flow**
```
Task completion and clarity. For each screen: what is the primary task, is the
primary action obvious within 3 seconds, and what is the shortest path to done?
Judge visual hierarchy (does the eye land on the right thing first), cognitive
load (competing elements, unnecessary choices), feedback (does the user learn the
result of every action), error recovery (can the user get out of the error state),
and dead ends (a state with no way forward). Compare loading/empty/error states
against the default state: does each one tell the user what happened and what to
do next? An empty state with no action is a finding. An error with no retry is a
finding.
```

**Visual UI**
```
Craft. Alignment to a grid, consistent spacing rhythm (are gaps from one scale or
arbitrary), type scale usage and heading hierarchy, color use and restraint,
density and breathing room, border/divider/shadow consistency, icon size and
optical alignment, image treatment. Then compare screens against each other: the
same concept must look the same everywhere. Name the measured or apparent value
and the value it should be.
```

**Design system**
```
Fidelity to the declared standard. Correct component variant for the job, all
interaction states present and distinct (rest/hover/focus/pressed/disabled),
values drawn from the spacing/type/shape/color scales rather than ad hoc, correct
elevation, correct navigation pattern for the window size class, and correct
dark-theme treatment. Every finding cites the specific rule from the standard
reference. Where the project has its own tokens, the tokens win — report drift
from them.
```

**Accessibility**
```
WCAG 2.2 AA. Start from the machine audit output, verify it against the images,
then cover what tools miss: focus visibility and order, target sizes, contrast in
both themes, information conveyed by color alone, form labelling and error
association, heading/landmark structure, announced status changes, behaviour at
200% text and 320px reflow, and largest OS font scale. Every finding cites its
success criterion number and the measured value versus the required value. Any
A/AA failure is P0.
```

**Responsive / adaptive**
```
The same screen across every captured viewport, orientation and font scale.
Look for horizontal overflow, clipped or truncated text, overlapping elements,
elements pushed off-screen, tables/charts that do not adapt, tap targets that
shrink below the minimum on small screens, wasted space on large screens, layout
that does not switch pattern at the right breakpoint, unsafe areas (notch, home
indicator, status bar), and keyboard overlap on mobile forms. Name the viewport
where each problem appears and the breakpoint that should have handled it.
```

**Content & product**
```
Words and expectations. Button labels that name the outcome (not "Submit"/"OK"),
headings that describe the content, empty states that explain why and what next,
error messages that say what happened and how to fix it (never a raw code or
stack trace), microcopy that sets expectations before a slow or destructive
action, consistent terminology for the same concept across screens, and no
untranslated or placeholder text. Propose the exact replacement string for every
copy finding.
```

---

## 6. Consolidation (main thread)

1. **Deduplicate.** Same defect from N reviewers → one finding, `corroborated: N`,
   highest severity reported, best-stated fix. Corroboration raises confidence, not
   severity.
2. **Resolve conflicts explicitly, by reviewer name**, with a decision and a reason.
   Tie-break order: accessibility > usability > design-system fidelity > visual
   preference. Record the losing position — the user may overrule.
3. **Drop findings that fail the contract** (§4). Report the count.
4. **Downgrade speculation.** Anything a static image cannot prove becomes a
   QUESTION in the report, not a P-rated finding.
5. **Group by fix, not by screen.** One token/theme/shared-component change often
   closes many findings — surface those first, they have the best ratio.
6. **Estimate effort** per fix group (`S` < 1h, `M` < half a day, `L` more) and mark
   `needs-design-decision` where the fix is a product choice rather than a defect.
7. **Order `FIX_PLAN.md`** by (severity, findings-closed / effort). That ordering is
   the deliverable — a flat list of 90 findings is not actionable.

---

## 7. Optional: verification reviewer (Phase 9)

After fixes, spawn **one** reviewer — a role that raised P0s, plus optionally
`Reality Checker` — on the `after/` screenshots only, with the finding list and
the instruction:

```
For each finding below, judge from the after/ screenshots alone:
fixed | partially fixed | not fixed | regressed — with the evidence for your call.
Do not introduce new findings unless they are regressions caused by the fixes.
```

This is what lets the final report say "improved" with something behind it.
