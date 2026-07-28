# Accessibility audit — WCAG 2.2 AA, with thresholds and tooling

Automated tools catch roughly a third of real accessibility problems. Run them
first because they are cheap and objective, then have the accessibility reviewer
do the part a tool cannot: semantics, order, labels that are technically present
but meaningless, and whether the screen is actually *usable* without sight or
without a mouse.

**Any WCAG A or AA failure is a P0 finding.** Not P1. Not "nice to fix".

---

## 1. Automated pass

### Web

```bash
pnpm add -D @axe-core/playwright axe-core
```

```ts
import AxeBuilder from '@axe-core/playwright'
const r = await new AxeBuilder({ page })
  .withTags(['wcag2a','wcag2aa','wcag21a','wcag21aa','wcag22aa','best-practice'])
  .analyze()
// → .ux-review/audits/<screen>__<state>.axe.json   (keep violations + nodes + impact)
```

Also available: `@storybook/addon-a11y` (same axe engine, per story, in the
Storybook UI), Lighthouse for a per-page score, `pa11y` for CI gates.

### Android
`AccessibilityChecks.enable()` in instrumented tests (Accessibility Test
Framework), plus the **Accessibility Scanner** app on the emulator for a
human-readable report per screen.

### iOS
`try app.performAccessibilityAudit()` in a UI test — reports contrast, hit
region, clipped text, missing labels, and element-description problems.

### Flutter
```dart
await expectLater(tester, meetsGuideline(textContrastGuideline));
await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
```

Record the results per screen×state in `.ux-review/audits/`. Aggregate the counts
by impact into `UX_REVIEW.md` — a table of violations per screen makes the
priority order obvious.

---

## 2. Thresholds — the numbers to check against

| Check | Threshold | WCAG |
|---|---|---|
| Body text contrast | **4.5:1** | 1.4.3 |
| Large text (≥24px, or ≥19px bold) contrast | **3:1** | 1.4.3 |
| UI components, icons, borders, focus rings | **3:1** | 1.4.11 |
| Target size (web) | **24×24 CSS px** min (48×48dp is the design-system target) | 2.5.8 |
| Target size (native) | 48×48dp Android · 44×44pt iOS | platform standard |
| Text resize | usable at **200%** with no loss of content or function | 1.4.4 |
| Reflow | no 2-D scrolling at **320 CSS px** width (≈400% zoom) | 1.4.10 |
| Text spacing overrides | no clipping with line-height 1.5×, paragraph 2×, letter 0.12em, word 0.16em | 1.4.12 |
| Focus visible | every focusable element has a visible indicator, ≥3:1 against adjacent colors | 2.4.7 |
| Focus not obscured | the focused element is not hidden behind a sticky header/footer | 2.4.11 |
| Color alone | no information conveyed by color only | 1.4.1 |
| Motion | honors `prefers-reduced-motion` / "reduce motion" | 2.3.3 |

---

## 3. Manual checks the reviewer must do (tools cannot)

**Keyboard (web) / focus traversal (native)**
- Tab through the whole screen: is the order the visual order?
- Is every interactive element reachable, and is nothing focusable that is not interactive?
- Can you escape every modal, menu and date picker (2.1.2 no keyboard trap)?
- Is there a skip-to-content link on long pages?
- Do custom widgets support the expected keys (Escape, arrows, Enter/Space, Home/End)?

**Screen reader model**
- Does the accessible name of each control say what it *does* ("Delete invoice
  #204", not "button", not "click here")?
- Is the heading structure a real outline (one h1, no skipped levels)?
- Are landmarks/regions present (`header`, `nav`, `main`, `footer` — or the native
  equivalents)?
- Are images either described or explicitly decorative?
- Are dynamic updates announced (`aria-live`/`role="status"`, `announceForAccessibility`,
  `Semantics(liveRegion: true)`) — 4.1.3? Toasts and validation errors most often fail here.
- Is the reading order of the accessibility tree sensible, and does it hide the
  decorative noise?

**Forms**
- Every input has a persistent visible label (placeholder-only is a failure).
- Errors: identified in text, next to the field, programmatically associated,
  focus moved or announced, and a suggestion for how to fix it (3.3.1–3.3.3).
- Required fields marked in text, not only with a red asterisk.
- Autocomplete attributes on personal data fields.
- No redundant re-entry of information already given (3.3.7).
- Authentication does not depend on a cognitive test like transcribing a code
  without paste support (3.3.8).

**Zoom, scaling and reflow**
- 200% text and 400% page zoom, at the narrowest viewport.
- Largest OS font scale on mobile.
- Landscape and small-height windows (a keyboard on screen halves the height).

**Cognitive and content**
- Plain, specific labels; no jargon-only actions.
- Destructive actions confirmable/undoable, and clearly marked.
- No time limits without an extension path.
- Consistent placement of help and navigation across screens (3.2.6).

---

## 4. States to audit that are usually forgotten

- **Error state** — is the error announced, focused, and phrased as a fix?
- **Loading state** — is it announced, or does the screen go silent?
- **Empty state** — is the reason conveyed in text, not only an illustration?
- **Disabled controls** — is the reason for being disabled available anywhere?
- **Dark mode** — recompute every contrast ratio; dark themes fail contrast at
  least as often as light ones.
- **High contrast / forced colors** — does the UI survive when the OS overrides colors?
- **RTL** — mirrored layout, icon direction, and no clipped text.

---

## 5. Reporting format for a11y findings

Every accessibility finding must carry the SC number so it is arguable and
verifiable, plus the measurement:

```markdown
### P0 · a11y · dashboard / default / mobile
**WCAG 2.2 · 1.4.3 Contrast (Minimum)**
Secondary metric labels render at 2.8:1 (#8A8A8A on #FFFFFF) — below the 4.5:1
required for body text.
Evidence: `screenshots/before/dashboard__default__mobile.png` (metric cards row)
· `audits/dashboard__default.axe.json` → `color-contrast` (4 nodes)
Fix: use `on-surface-variant` from the theme (measured 4.7:1) instead of the
hard-coded `#8A8A8A` in `MetricCard.tsx:34`.
```

State the measured value and the required value. "Low contrast" without a ratio
is not actionable and will be dropped in consolidation.
