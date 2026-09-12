---
name: better-colors
description: OKLCH color space and color usage for web projects. Check contrast, handle gamut boundaries, and apply color with meaning. Triggers on oklch, contrast ratio, gamut, display p3, design tokens, semantic color tokens, hue drift, chroma, dark mode colors, color meaning, light and dark appearance.
---

# OKLCH Colors

OKLCH is a perceptually uniform color space where lightness, chroma, and hue are useful design controls. Use it when the project already uses OKLCH, when creating a new color system, or when the user asks for conversion or palette work.

## Core Principles

### 1. Use a Perceptual Color Space

- **Respect the existing system.** Do not convert notation merely because this skill was loaded. Reuse the project's semantic tokens and authoring format unless the task includes a color-system migration.
- **Perceptual uniformity.** Equal L steps = equal brightness. `oklch(0.5 ...)` is visually mid. HSL's `lightness: 50%` varies wildly by hue.
- **Stable hue.** HSL blue shifts toward purple as lightness changes. OKLCH hue stays constant across the full lightness range.
- **Independent chroma.** Chroma is an absolute measure of colorfulness that doesn't depend on lightness. HSL saturation does.
- **Finite gamut.** Not every oklch value maps to a displayable sRGB color. High-chroma values at certain hues will clip; gamut awareness is required.

### 2. Write and Format OKLCH Consistently

```
oklch(L C H)
oklch(L C H / alpha)
```

| Channel | Range | Description |
| --- | --- | --- |
| L (Lightness) | 0–1 | 0 = black, 1 = white. Perceptually uniform. |
| C (Chroma) | 0–~0.4 | Colorfulness. 0 = gray. Max depends on L and H. |
| H (Hue) | 0–360 | Hue angle in degrees. |
| alpha | 0–1 | Optional transparency. Slash syntax. |

Use three decimal places for L and C and up to three for H. Drop trailing zeros and format `-0` as `0`.

### 3. Measure Contrast, Gamut, and Palette Behavior

| Rule | Value |
| --- | --- |
| Light/dark boundary | L > 0.73 = light background → dark text; below it, light text still scores higher |
| Lightness gap (light bg) | Foreground L < 0.35 when background L > 0.9 |
| Lightness gap (dark bg) | Foreground L > 0.9 when background L < 0.25 |
| Hue drift threshold | > 10° spread across palette steps = visible drift |
| APCA body text | \|Lc\| >= 75 minimum, >= 90 preferred |
| APCA non-body text | \|Lc\| >= 60 minimum |
| WCAG 2 normal text | 4.5:1 AA, 7:1 AAA |
| Contrast fix (only when asked) | Adjust L first; preserve C and H when possible, then remeasure the rendered pair |

## Common Mistakes

| Issue | Fix |
| --- | --- |
| Failing contrast | Report the pair, its measured Lc and the threshold it misses; change colors only when asked (then adjust L, keep C and H) |
| Same absolute C across different hues | Use same C% (percentage of max) for consistent vividness |
| P3 color without sRGB fallback | Add `@media (color-gamut: p3)` pattern |
| Dark mode created by mechanically reversing the light palette | Use the light palette as a starting point, then tune chroma and lightness and recheck every foreground/background pair |
| Same hue means two different things (link color reused decoratively) | One color, one meaning; give the second use a neutral |
| Semantic token used outside its role (separator as text) | Add a token for the missing role; never borrow by value |
| Several colored control backgrounds in one view | Fill only the single primary action; secondaries stay neutral |
| Palette verified only in light mode | Recheck every foreground/background pair in both appearances |

## Review Output Format

Use this format only when the user asks for a standalone color review. When a coordinating skill (such as `better-interface` or `frontend-audit`) orchestrates the review, defer entirely to its [canonical finding contract](../better-interface/SKILL.md#canonical-finding-contract) for output format, consolidation rules, and verdict.

- **Severity**: `P0` makes content unreadable or assigns a dangerous semantic color; `P1` causes a significant contrast or theme failure; `P2` is repeated token, gamut, or semantic-role drift; `P3` is isolated color refinement.
