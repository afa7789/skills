---
name: visual-test
description: Record what happens when clicking through an app, as a click-through video plus per-step screenshots. Use for a visual or E2E test of a flow, "record this flow", "grava o fluxo", "click through the app and show me", "what happens when I click X", or finding dead buttons.
---

# Visual test: click through, record, report

`<skill>` is the directory holding this SKILL.md. `<skill>/scripts/record.mjs` drives the browser
and records; you write the flow and judge the result. Run it with cwd = the project: it loads
`playwright` from there (exit 2 prints the `npm i -D playwright` line to run).

## Flow mode: a journey the user describes

1. Turn the plain-words request ("grava o que acontece clicando no cadastro") into
   `ux/flows/<name>.json`. Read the page or the UI code for the real labels; never guess them.

```json
{"name": "signup", "start": "/", "steps": [
  {"click": "Sign up"}, {"fill": {"Email": "test@example.com", "Password": "test-only-1"}},
  {"press": "Enter"}, {"expect": "Welcome"}, {"expect": {"url": "/dashboard"}},
  {"goto": "/settings"}, {"wait": 500}]}
```

   `click` takes an accessible name: button, then link, then label, then visible text. `fill`
   takes a field label, or its placeholder. `expect` takes visible text, or `{"url": ...}` for a
   URL substring. Each step gets 5 s; the first failing step stops the flow.
2. Run it. Pass `--start` only if the app is not already running; `--headed --slowmo 300` to watch.

```bash
node <skill>/scripts/record.mjs --url http://localhost:5173 --flow ux/flows/signup.json \
  [--start "npm run dev"] [--wait 60] [--out ux/flows/signup] [--viewport 1440x900] [--headed] [--slowmo 0]
```

Into `--out` (default `ux/flows/<name>`) it writes `step-NN-<action>.png` per step (step 00 is the
start route), `flow.webm` and `flow.md`, a table of steps. Stdout has one line per step,
`NN <action> "<target>" ok|FAIL url=<path> console=<n> <png>`, then `FLOW PASS|FAIL <name> video=<path>`.
Exit 1 on a failed step; a console error fails its step, as in `ux` and explore mode. Dismissed
dialogs are listed, not failed on.

## Explore mode: find dead buttons

```bash
node <skill>/scripts/record.mjs --url http://localhost:5173 --explore --routes / /pricing [--max 30] [--all]
```

Per route it clicks each visible link and button from a fresh load and labels it `nav`, `dialog`,
`change`, `popup`, `DEAD` (nothing happened) or `ERROR` (console error or HTTP >= 400). Disabled,
external and `mailto:`/`tel:` links are `skipped`, and so are destructive names (delete, logout,
pay, excluir, sair...) unless `--all`: use that only against a disposable environment. Into `--out`
(default `ux/flows/explore`) it writes `<slug>-NN.png` per click and `<slug>.webm` per route (`/` is
`root`), ends with `EXPLORE PASS|FAIL <n> clicks <d> dead <e> errors`, exits 1 on `DEAD` or `ERROR`.

## Report

1. Read every step PNG. Say where the video is.
2. Per step, failures first: action, what was expected, what the screenshot shows, URL.
3. Dismissed dialogs are findings even when the step passed.
4. Claim only what a PNG or a stdout line shows.

## Regression check

A passing flow becomes a dagRobin task `metadata.check`, with `<skill>` as an absolute path. Checks
run in a fresh worktree, so install first:
`npm ci --silent && node <skill>/scripts/record.mjs --flow ux/flows/<name>.json --url http://localhost:5173 --start "npm run dev"`

## Rules

- Test environment and fake data only. Never put real credentials or personal data in a flow:
  the screenshots and video capture everything typed. `flow.md` lists field labels, not values.
- For static screenshots at phone and desktop width with a UI rubric, use the `ux` skill. For a
  full journey audit (flow map, friction, findings), follow the `ux` skill's `reference/flows.md`
  and use this recorder for its videos and step shots.
