# Design standard reference — Material Design 3 (plus HIG / Fluent notes)

Use this to turn "the spacing feels off" into a checkable violation with a
number. Every finding from the design-system reviewer should cite a rule from
here (or from the project's own token file, which always wins over the standard).

**Order of authority:** the project's design tokens → the standard it claims to
follow → this file. If the project has a token file, audit against *it* and report
drift; do not impose Material 3 on a product that has its own system.

---

## 1. Layout and spacing

- **Base grid: 4dp.** Every margin, padding, gap and component size is a multiple
  of 4. Values like 5, 7, 13, 18 are drift — flag them.
- **8dp** for most component-internal spacing, **16dp** for content gutters on
  compact screens, **24dp** on medium and larger.
- **Touch target: minimum 48×48dp**, regardless of the visual size of the icon.
  Adjacent targets need spacing so the hit areas do not merge.
- Keep line length readable: roughly 40–75 characters for body text.

### Window size classes (breakpoints)

| Class | Width (dp) | Typical layout |
|---|---|---|
| Compact | 0–599 | single pane, bottom nav |
| Medium | 600–839 | single pane + nav rail, or list-detail on tablet portrait |
| Expanded | 840–1199 | list-detail, nav rail or drawer |
| Large | 1200–1599 | list-detail with wider panes, permanent drawer |
| Extra-large | ≥1600 | capped content width, extra pane |

Audit at **at least one width per class the product supports**, and always at the
narrowest one — that is where overflow appears.

---

## 2. Type scale

15 named roles. Using an ad-hoc font size instead of a role is drift.

| Role | Size / Line height | Weight |
|---|---|---|
| Display Large / Medium / Small | 57/64 · 45/52 · 36/44 | 400 |
| Headline Large / Medium / Small | 32/40 · 28/36 · 24/32 | 400 |
| Title Large / Medium / Small | 22/28 · 16/24 · 14/20 | 400 / 500 / 500 |
| Body Large / Medium / Small | 16/24 · 14/20 · 12/16 | 400 |
| Label Large / Medium / Small | 14/20 · 12/16 · 11/16 | 500 |

Checks: no body text below 12sp/12px; no more than ~3 type roles competing in one
view; heading hierarchy monotonic (no Headline Small above a Display Large in the
same section); line height never smaller than the font size.

---

## 3. Color roles

Never a raw hex in a component. The role pairs guarantee contrast:

```
primary / on-primary            primary-container / on-primary-container
secondary / on-secondary        secondary-container / on-secondary-container
tertiary / on-tertiary          tertiary-container / on-tertiary-container
error / on-error                error-container / on-error-container
surface / on-surface            surface-variant / on-surface-variant
surface-container-lowest | low | (base) | high | highest
outline (borders) · outline-variant (dividers) · scrim · shadow
inverse-surface / inverse-on-surface / inverse-primary
```

Rules to audit:

- Text on a surface uses that surface's `on-*` role — a mismatched pair is the
  single most common cause of a contrast failure.
- One primary action per view; `primary` is not decoration.
- Error state uses `error`/`on-error`, never an arbitrary red.
- Dark theme is a different tonal mapping, **not** an inverted light theme.
  Check surfaces separately in dark mode; elevation is expressed with
  `surface-container-*` tones rather than heavy shadows.

---

## 4. Elevation and shape

| Level | Elevation | Typical use |
|---|---|---|
| 0 | 0dp | page surface |
| 1 | 1dp | cards at rest, elevated buttons |
| 2 | 3dp | app bars on scroll, FAB at rest |
| 3 | 6dp | dialogs, pickers, FAB pressed |
| 4 | 8dp | navigation drawer |
| 5 | 12dp | rarely — highest overlays |

Shape scale: `none 0 · extra-small 4 · small 8 · medium 12 · large 16 ·
extra-large 28 · full (pill)`. A corner radius outside the scale is drift; mixed
radii inside one card is a visual-consistency finding.

---

## 5. Interaction states

Every interactive component needs all of these, visibly distinct:

| State | State-layer opacity over the content color |
|---|---|
| Hover | 8% |
| Focus | 10% |
| Pressed | 10% |
| Dragged | 16% |
| Disabled | content 38%, container 12% |

Audit: is there a **visible focus indicator** (not only a color shift)? Is
`disabled` distinguishable from `enabled` without relying on color alone? Do
pressed/ripple states exist on custom components, or only on the library ones?

---

## 6. Motion

Durations: short 50–200ms · medium 250–400ms · long 450–600ms · extra-long
700–1000ms. Emphasized easing for entering/persistent elements, standard easing
for small utility transitions. Everything must respect
`prefers-reduced-motion` / "reduce motion" — an animation with no reduced-motion
path is a P0 accessibility finding.

---

## 7. Component checks worth running per screen

- **App bar** — correct variant (small/medium/large/center-aligned), scroll
  behaviour, title truncation with a long title.
- **Navigation** — bottom bar (3–5 destinations) on compact, rail on medium,
  drawer on expanded+. Current destination clearly indicated.
- **Buttons** — one filled button per view as the primary action; correct variant
  hierarchy (filled > tonal/elevated > outlined > text); 40dp height; icon+label
  spacing.
- **Text fields** — filled or outlined consistently (not both), label/placeholder
  not conflated, helper text reserved so the layout does not jump when an error
  appears, error text present *and* an error icon or other non-color cue.
- **Cards / lists** — consistent density and padding; dividers via
  `outline-variant`; list item heights from the standard (one/two/three line).
- **Dialogs / sheets** — the action order the platform expects, dismissal
  affordance, scrim, focus trapping, and content that scrolls.
- **Snackbar / toast** — not the only channel for critical errors; long enough to
  read; action reachable.
- **Empty state** — illustration or icon, a sentence explaining *why* it is empty,
  and a primary action. An empty list with no text is a P1.
- **Loading** — skeletons that match the final layout (no jump), or a progress
  indicator; no unbounded spinner with no timeout/error path.

---

## 8. Token-drift detection (mechanical, run it)

Grep the styling layer for hard-coded values that bypass the system:

```bash
# hex colors outside the token/theme files
rtk grep -rn "#[0-9a-fA-F]\{3,8\}" --include=*.css --include=*.scss --include=*.ts --include=*.tsx --include=*.vue --include=*.svelte
# odd pixel values (non-multiples of 4)
rtk grep -rnE "[^0-9-](1|2|3|5|6|7|9|10|11|13|14|15|17|18|19|21|22|23)px" --include=*.css --include=*.scss
# arbitrary Tailwind values, which bypass the scale entirely
rtk grep -rn "\[[0-9]\+px\]" --include=*.tsx --include=*.vue --include=*.svelte
# Flutter / Compose hard-coded sizes
rtk grep -rn "EdgeInsets.all([^48]" --include=*.dart ; rtk grep -rn "\.dp" --include=*.kt
```

Report the count per file and the worst offenders. This is usually the highest
leverage fix in the whole report: one token pass closes dozens of P2 findings.

---

## Appendix — other standards

**Apple HIG (iOS/macOS):** minimum tap target 44×44pt; use Dynamic Type text
styles rather than fixed sizes and test at the largest accessibility size; respect
safe areas and the home indicator; system materials/blur for layering; standard
navigation patterns (nav bar back, swipe-back, sheets with grabbers); SF Symbols
sized with the text style.

**Fluent 2 (Microsoft):** 4px base grid; type ramp roles (Caption→Display);
semantic color tokens with light/dark/high-contrast variants — high contrast is a
first-class mode, audit it; elevation via shadow tokens.

**Custom system (`standard: custom:<path>`):** load the project's token file and
build the audit rules from it — allowed spacing scale, type roles, color roles,
radii. Every value used outside that set is drift. This is strictly better than
imposing an external standard, so prefer it whenever tokens exist.
