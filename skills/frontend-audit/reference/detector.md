# Deterministic frontend detector

Run from the target project:

```bash
node <skill>/scripts/detect-ui.mjs --json src
node <skill>/scripts/detect-ui.mjs --config .ui-quality.json src/app.tsx
```

The detector scans HTML, CSS, JavaScript/TypeScript (including JSX, modules, and MDX), Vue, Svelte, and Astro sources. It skips dependencies, generated output, captures, and build directories. Exit code `1` means at least one `error`; warnings and advisories do not fail the command. Exit code `2` means the detector itself failed, including an invalid target.

## Rule classes

- `error`: objective access or runtime breakage; inspect as P0.
- `warning`: probable user or system harm; assign P1 or P2 from impact and reach.
- `advisory`: contextual design heuristic; at most P3 and never enforce against a confirmed brief.

The initial registry covers disabled zoom, positive tabindex, non-semantic click targets, missing image alternatives, focusable `aria-hidden` elements, autoplay without controls, empty link targets, missing button types, removed focus outlines, raw HTML sinks, transition-all, tiny text, skipped heading levels, nested cards, gradient text, directional CSS, and decorative pulse.

## Intentional exceptions

Copy [`../assets/ui-quality.example.json`](../assets/ui-quality.example.json) to `.ui-quality.json` only when the project needs exceptions. Keep ignores narrow and explain them in review output.

- `ignoreRules`: suppress a rule globally; avoid this for `error` rules.
- `ignoreFiles`: glob patterns for generated or legacy surfaces.
- `ignores`: narrow by `rule`, `file`, and/or exact evidence text.

Detector output is evidence to inspect. Browser behavior, the product/design context, and the owning `better-*` skill decide whether a warning or advisory becomes a finding.
