# Capture contract — shared across every platform

Platform recipes live in [`web.md`](web.md) and [`mobile.md`](mobile.md). This file
is the part that must be **identical everywhere**, because the report, the audits
and the before/after comparison all depend on it.

---

## 1. The shot matrix

Expand `ui-catalog.yaml` into the full list of images before capturing anything.
The matrix is the cross product:

```
screens × states × viewports × themes × [font-scale variants]
```

Do not silently reduce it. Reduce it *explicitly*, with the user, and record the
reduction in `SCREEN_INVENTORY.md`. Sensible reductions:

- Font-scale variants only for text-heavy screens and forms (not every screen).
- Dark theme only if the app actually themes (grep for the theme switch first).
- Tablet only if the product supports it.

Sanity-check the count before starting: `screens × states × viewports` grows fast.
40 screens × 4 states × 3 viewports × 2 themes = 960 images. Tell the user the
number and the rough runtime, and offer a scoped subset (one flow, one viewport)
if it is unreasonable.

---

## 2. Naming — fixed, not negotiable

```
.ux-review/screenshots/<before|after>/<screen-id>__<state>__<viewport>[__dark][__fs200].png
```

- `screen-id` — exactly the `id` from `ui-catalog.yaml` (kebab-case, stable).
- `state` — exactly a state name from that screen's `states` list.
- `viewport` — exactly a `viewports[].name` (or `devices[].name` on native).
- Suffixes only for variants: `__dark`, `__fs200` (200% font scale), `__rtl`, `__landscape`.
- Separator is a double underscore; never spaces, never nested folders per screen.

The comparison step pairs `before/X.png` with `after/X.png` by filename alone. A
renamed file is a lost comparison.

---

## 3. Determinism — the one rule that matters

**Two runs of the same commit must produce byte-comparable images.** Verify this
*before* trusting any before/after diff: capture the matrix twice on the same
commit and diff the two runs. If anything differs, fix the harness first — an
unstable baseline makes every later claim worthless.

Sources of nondeterminism, in order of how often they bite:

| Source | Fix |
|---|---|
| Web fonts loading late | await `document.fonts.ready`; bundle fonts locally |
| Animations / transitions / spinners mid-frame | disable globally; for spinners, freeze or accept a masked region |
| Live clock, relative timestamps | freeze the clock (`page.clock`, injected clock, status-bar override) |
| Real network / real backend | intercept everything; `onUnhandledRequest: 'error'` |
| Random or generated data | seeded fixtures only |
| Remote images / avatar services | local fixture assets |
| Locale / timezone from the machine | pin both explicitly |
| Scroll restoration, virtualized lists | reset scroll; force render or capture at a fixed offset |
| Device/emulator variance | pin the exact device model and DPR; same OS image |
| Caret blink, focus ring on load | hide caret; blur on load unless focus is the subject |
| Video/canvas/WebGL content | mask the region rather than fight it |

For genuinely dynamic regions, mask instead of excluding the screen:
Playwright `mask: [locator]`, or a fixed clip rect. Record every mask in
`SCREEN_INVENTORY.md` so a reviewer knows a region was hidden on purpose.

---

## 4. What to capture per screen

- **Full page**, not just the viewport — truncation below the fold is a real defect.
- **Plus the first viewport alone** for above-the-fold hierarchy judgement, when
  the page is long. Reviewers judge "what do I see first" from that shot.
- **Interaction states that need a click** (menu open, dropdown expanded, invalid
  form, toast visible) as their own state entries with their own shots — reached
  by a `play` function (Storybook) or a flow step (Maestro).
- **Focus state** of the primary action, for the keyboard/a11y reviewer.

---

## 5. Failure logging

Every screen in the catalog ends up in exactly one of three buckets:

1. captured,
2. captured with a caveat (masked region, state faked, param substituted),
3. **failed** — logged in `.ux-review/audits/capture-failures.md` with the reason
   (auth unavailable, crash, unresolvable param, native-only surface, flaky timeout).

A failed capture must appear in `UX_REVIEW.md` as an explicit gap. Never let a
screen vanish between the catalog and the report — a silent omission reads as
"reviewed and fine".

---

## 6. Comparison (Phase 9)

1. Same harness, same seed, same clock, same device, same commit-of-the-harness.
   If the harness changed, re-capture `before/` from the pre-fix commit rather
   than comparing across harness versions.
2. Pair by filename; report `new`, `removed`, `changed`, `identical`.
3. For each `changed` pair, write the diff image into `comparisons/`.
4. Cross-reference every diff against `FIX_PLAN.md`: an image that changed with
   **no** corresponding planned fix is an unintended regression — investigate it.
5. Re-run the Phase 6 audits and diff the numbers, not just the pixels. Fewer axe
   violations and better contrast ratios are the actual proof; pixels only show
   that something moved.
