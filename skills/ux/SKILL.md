---
name: ux
description: Spin up the app, screenshot it at phone and desktop width, evaluate the UI and improve it. Use for a UX or UI review, "screenshot this page", "the UI looks off", polishing a screen, auditing a user flow, or checking a frontend change in the real app.
---

# UX loop: shoot, judge, fix, re-shoot

`<skill>` is the directory holding this SKILL.md. `<skill>/scripts/shoot.mjs` does the mechanical
part; you do the judgment. Run it with cwd = the project: it loads `playwright` and
`@axe-core/playwright` from there (exit 2 prints the `npm i -D` line to run).

```bash
node <skill>/scripts/shoot.mjs --url http://localhost:5173 --routes / /login \
  [--start "npm run dev"] [--wait 60] [--out ux/shots/before]
```

Per route it shoots 390×844 and 1440×900 full-page PNGs and prints one line per screen:
`<route> <w>x<h> console=<n> axe=<n> empty=<yes|no> <png>`, then `SHOOT PASS|FAIL <n> screens`.
Exit 1 when any screen has a console error, a serious/critical axe violation or an empty main,
so it works as a dagRobin task `check`.

## Loop

1. Find how the app runs: `package.json` scripts (`dev`, `start`, `preview`), `Makefile`, README.
   Note the URL. List the routes from the router config or `pages/`/`app/` directories.
2. Shoot into `ux/shots/before`. Pass `--start` only if the app is not already running.
3. Read every PNG at both viewports. Script failures are findings too.
4. Judge each screen against the rubric. Rank: blocks a task > misleads > slows > polish.
5. Fix the highest-impact issues in one batch. Touch only what the findings name.
6. Shoot the same routes into `ux/shots/after` and read those PNGs.
7. Stop after 2 rounds at most. Report the before/after paths, what was fixed, and what remains.
   Claim a fix only if an after shot or a script line shows it.

## Rubric

- Empty, loading and error states exist and say what to do next.
- Every CTA leads somewhere; no dead buttons or `#` links.
- At 390px all content is reachable (wraps, scrolls or moves into a menu), not just "no overflow".
- Every input has a real label; a placeholder is not a label.
- A modal traps focus, closes on Esc and returns focus to its trigger.
- Status is never shown by color alone; pair it with text or an icon.
- Targets are at least 24px, 44px on touch.
- Never show a raw enum, ISO date, `undefined`, `NaN` or `[object Object]`.
- Rate-limit and error messages say what happened and when to retry.
- Motion respects `prefers-reduced-motion`.
- One primary action per view.
- Copy matches the product's language and terminology.

Focus, Esc and motion items need interaction or code reading; a still screenshot cannot prove them.

For a full journey audit (sign-up, checkout, error recovery) with video and per-step evidence,
follow `reference/flows.md`.
