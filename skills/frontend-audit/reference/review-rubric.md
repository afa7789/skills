# Review panel — roles, prompts, finding contract, consolidation

The panel exists to produce **evidence-backed, actionable findings**, not opinions.
Six independent reviewers, spawned as real parallel `Agent` calls, each judging
the same screenshots from a different mandate.

---

## 1. Panel composition

| # | Reviewer | `subagent_type` | `/better-*` skill | Mandate |
|---|---|---|---|---|
| 1 | Accessibility | `Accessibility Auditor` | `better-accessibility` | WCAG 2.2 AA, contrast, focus, semantics, screen-reader model, scaling |
| 2 | Layout & responsive | `Frontend Developer` | `better-layout` | Grouping, alignment, spacing rhythm, breakpoints, overflow, safe areas |
| 3 | Content & product | `Product Manager` | `better-writing` | Labels, microcopy, empty states, error messages, action clarity |
| 4 | Visual UI & polish | `UI Designer` | `better-ui` | Animations, shadows, border radius, icons, motion, micro-interactions |
| 5 | Typography | `UI Designer` | `better-typography` | Font choice, type scale, line-height, wrapping, truncation |
| 6 | Color & tokens | `UI Designer` | `better-colors` | Contrast measurement, palette consistency, semantic tokens, dark mode |

Every reviewer **MUST load its `/better-*` skill** via the `skill` tool before judging.
The skill's **Core Principles** are the judgement rubric; its **Common Mistakes**
table is a pre-flight checklist. Every finding cites the violated principle by name
from the loaded skill.

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
5. The resolved `PRODUCT.md`, `DESIGN.md`, and surface brief paths, visitor mode, change boundary, and intentional exceptions.
6. The **finding contract** (§4) — verbatim.

Reviewers get read access to the code so they can point at the exact line to
change, but they **must not edit anything**.

---

## 3. Per-reviewer prompt template

```
FIRST: Load your domain skill via the skill tool:
  skill("{SKILL_NAME}")

Then proceed with the review below. Apply the skill's Core Principles as your
judgement rubric and check its Common Mistakes table against every screen.

---

You are the {ROLE} reviewer on an independent UI/UX audit panel. Five other
reviewers are auditing the same screens from different mandates; you cannot see
their work and must not speculate about it. Judge only what your mandate covers —
another reviewer owns everything else.

YOUR MANDATE:
{MANDATE_BLOCK}          # from §5 below, verbatim

SKILL APPLIED:
You loaded `{SKILL_NAME}`. Apply its Core Principles by name in every finding.
Check the Common Mistakes table — any match is an automatic finding.

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
**Location:** {source file:line, or exact screen component when source is unavailable}
**Evidence:** {screenshot filename} — {where in the image: region, component, text}
  (+ audit entry, if any)
**Why it matters:** the concrete user consequence. No abstractions.
**Principle:** the skill principle violated, by name.
**Fix:** the specific change — property, token, value, component, or copy.
  Name the file:line when you can find it in the code.
**Confidence:** high | medium (medium = might be a screenshot artifact)
**Owner:** accessibility | layout | writing | typography | colors | ui
**Verification:** verified | not-verified — {check or missing evidence}

SEVERITY (use exactly these):
P0 blocks a core task, hides content or controls, risks data loss, causes a runtime failure, or creates a WCAG A/AA barrier
P1 significantly harms comprehension, completion, recovery, responsiveness, or trust
P2 repeated design-system, consistency, or maintainability problem
P3 isolated refinement or contextual advisory

HARD RULES:
- No visual finding without a screenshot reference. A machine/source finding instead needs the exact audit entry and source location.
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

A finding survives consolidation only if it has: severity, confidence, owner,
location, evidence, user impact, proposed change, and verification status. Visual
findings also require a screen/state/viewport anchor and screenshot reference.
Drop the rest and report how many were dropped and why.

Categories (keep the vocabulary fixed so the report is groupable):
`a11y` · `contrast` · `layout` · `spacing` · `typography` · `color` · `hierarchy` ·
`feedback` · `state-coverage` · `consistency` · `design-system` · `responsive` ·
`content` · `navigation` · `performance-perceived`.

---

## 5. Mandate blocks (paste verbatim into each prompt)

**Accessibility** (→ `better-accessibility`)
```
WCAG 2.2 AA. Start from the machine audit output, verify it against the images,
then cover what tools miss: focus visibility and order, target sizes, contrast in
both themes, information conveyed by color alone, form labelling and error
association, heading/landmark structure, announced status changes, behaviour at
200% text and 320px reflow, and largest OS font scale. Every finding cites its
success criterion number and the measured value versus the required value. Any
A/AA failure is P0.
Apply every Core Principle from better-accessibility — especially Native Elements
First, Visible Focus Rings, Errors That Announce, Minimum Hit Area, and Honor
prefers-reduced-motion. Cross-check the Common Mistakes table.
```

**Layout & responsive** (→ `better-layout`)
```
Spatial structure across every captured viewport, orientation and font scale.
Audit grouping (space vs lines), alignment edges, reading order, progressive
disclosure cues, and adaptive breakpoints. Look for horizontal overflow, clipped
or truncated text, overlapping elements, elements pushed off-screen, tables/charts
that do not adapt, tap targets that shrink below the minimum, wasted space on
large screens, and unsafe areas (notch, home indicator, status bar). Name the
viewport where each problem appears and the breakpoint that should have handled it.
Apply every Core Principle from better-layout — especially Group with Space Not
Lines, Align to Shared Edges, Hold Structure Until It Breaks, and Plan for Growth
and Clipping. Cross-check the Common Mistakes table. Use logical properties
(padding-inline-start, margin-inline-end); flag physical left/right in
direction-dependent layout.
```

**Content & product** (→ `better-writing`)
```
Words and expectations. Button labels that name the specific outcome (verb-first,
never "OK"/"Submit"), headings that describe the content, empty states that explain
why and what next, error messages that say what happened and how to fix it (never
a raw code or stack trace), microcopy that sets expectations before slow or
destructive actions, consistent terminology across screens, and no untranslated or
placeholder text. Propose the exact replacement string for every copy finding.
Apply every Core Principle from better-writing — especially Verb-First Buttons,
Errors Say How to Fix, Empty States Point Forward, Links Describe Their
Destination, and Settings Describe the ON State. Cross-check the Common Mistakes
table.
```

**Visual UI & polish** (→ `better-ui`)
```
Craft and micro-interactions. Concentric border radius, optical alignment over
geometric, shadows for elevation (borders for structure), interruptible
animations, staggered entrances for infrequent sequences, subtle exits, contextual
icon animations (scale 0.25→1, opacity 0→1, blur 4px→0px), image outlines
(oklch(0 0 0 / 0.1) light / oklch(1 0 0 / 0.1) dark), scale(0.96) on press, and
motion restraint. Walk every state (hover, focus, active, loading, empty) and
inspect animations at 10% speed if possible.
Apply every Core Principle from better-ui — especially Concentric Border Radius,
Scale on Press, Contextual Icon Animations, Never Use transition:all, and Motion
Restraint. Cross-check the Common Mistakes table.
```

**Typography** (→ `better-typography`)
```
Text rendering quality. Font format (.woff2), variable font property usage
(font-weight over font-variation-settings), type scale consistency, heading
hierarchy (sizes descend with level, semantic elements from better-accessibility),
unitless line-height (1.1 headings, 1.5-1.6 body), deliberate wrapping (balance
headings, pretty descriptions), tabular numbers on changing values, truncation
with recovery path, underlines from font metrics, 16px inputs on mobile, measure
capped at 60-75ch, antialiased root, and text-selectable by default.
Apply every Core Principle from better-typography — especially Properties Over Raw
Tags, Heading Sizes Descend with Level, Line-Height by Role, Cap the Measure,
and Inputs at 16px on Mobile. Cross-check the Common Mistakes table.
```

**Color & tokens** (→ `better-colors`)
```
Color system integrity. Contrast ratios (measure rendered pairs, report Lc and
threshold), palette consistency (constant oklch hue, C% for vividness), gamut
safety (sRGB fallback for P3), semantic token usage (one color, one meaning),
dark mode parity (recheck every foreground/background pair in both appearances),
and restraint (fill only the primary action; secondaries stay neutral).
Apply every Core Principle from better-colors — especially Use a Perceptual Color
Space, Measure Contrast Gamut and Palette Behavior, and the Common Mistakes table.
Never change project colors unless asked; report the pair, measurement, and
threshold missed.
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
