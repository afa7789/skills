# Skills & rules for coding agents

![imagem de skills](resources/image.png)

Prompt assets for Claude Code, OpenCode, Codex CLI, Hermes Agent, [Pi](https://pi.dev/) and [OMP](https://omp.sh/).
One script, `scripts/sync-skills.sh`, installs them into all six. v1 lives at tag `v1.0.0`; v2 is a rewrite from principles.

## Principles

1. Think before coding; surface tradeoffs.
2. Ponytail: code that doesn't need to exist isn't written.
3. Surgical changes; SoC and SOLID.
4. **Binary proof per task**: every task names one check that exits 0 when done. Features first (smoke checks),
   hardening after (failing test first, run targeted — not on every CI run). No coverage % gate.
5. Gates over prose: whatever can be checked is a script, linter rule or hook.
6. Multi-agent only for independent work; the loop lives outside the model.

## Layers

| Layer | Where | Loaded |
|---|---|---|
| Rules | `global/CLAUDE.md` + `rules/*.md` (≤ 80 lines, gated) | every session, every host |
| Skills | `skills/<name>/SKILL.md` | on demand, by description |
| Checks | scripts inside each skill, dagRobin `verify` | executed, never read |

## Skills

| Skill | What it does |
|---|---|
| `fdd` | Brief or repo → canonical feature graph → dagRobin tasks, each with one binary `metadata.check` |
| `dag-loop` | External bash driver: claims ready tasks, runs a worker per git worktree on any of the six hosts, `dagRobin verify` decides done |
| `ux` | Spin up the app, screenshot (Playwright + axe), evaluate, fix, re-shoot |
| `visual-test` | Record a click-through: flow video, a screenshot per step, console errors, dead buttons; exits 0/1 |
| `tdd` | On demand: red → green → refactor with binary evidence, for hardening tasks and bug fixes |
| `review` | PR/branch review: binary spec check, then bugs, trust boundaries and the ponytail lens |
| `summarize` | Summarize/audit the documents you point at → `SUMMARY.md` (status, drift, open items) |
| `estimator` | Token, USD and calendar estimate calibrated on git history and session usage |
| `prompt-refiner` | Sharpen a vague idea into a brief (input for `fdd`) |
| `peer-review` | Panel of independent subagents rewrites and cross-reviews a document |
| `solidity-review` / `solidity-complex-audit` | Solidity checklist review / full multi-phase audit |
| `ste-docs` / `reader` | Simplified Technical English rewrite / proofreading |

Feature pipeline: `prompt-refiner` → `fdd` → `dag-loop` → `review`.

## Install

```bash
bash scripts/install-tools.sh      # Rust + dagRobin (needs >= 0.2.0 for `verify`)
bash scripts/sync-skills.sh --status   # dry run
bash scripts/sync-skills.sh            # sync all installed hosts (backups kept)
```

The sync translates frontmatter per host, writes each host's global instructions from the rules,
and prunes v1 skills and agents by name (your own agents are never touched).

## herdr

`bash scripts/herdr-install.sh` links `herdr/` as the herdr plugin `skills.dagloop` and adds keys:
`prefix+alt+w` watch the dag-loop log, `prefix+alt+r` start dag-loop, `prefix+alt+s` dagRobin status.
`dag-loop` sends herdr notifications on done/blocked/stop when run inside herdr. Undo: `--uninstall`.

## Develop

```bash
git config core.hooksPath .githooks   # once per clone: pre-push runs the gate
bash scripts/gate.sh                  # shellcheck + sync suite + skill tests + line budgets
node skills/ux/tests/shoot.e2e.mjs    # browser e2e, on demand (needs npx + Chromium)
```

New skill: `skills/<name>/SKILL.md` with `name` and a trigger-focused `description`, ≤ 100 lines.
Tests go in `skills/<name>/tests/` as `*.test.sh` (run by the gate) or `*.e2e.mjs` (on demand);
never `*.test.mjs` (those gate every sync).
