# Prompt-asset repository

Skills and rules for Claude Code and six sibling hosts (OpenCode, Codex, Hermes, Pi, OMP, Antigravity).

- **Layers.** `global/CLAUDE.md` + `rules/*.md` are loaded by every host in every session: keep them ≤ 80 lines total
  (`scripts/gate.sh` enforces it). `skills/<name>/SKILL.md` loads on demand. Anything checkable is a script inside its skill.
- **Sync.** `bash scripts/sync-skills.sh` (`--status` dry run, `--only=<host>` one host). Never copy files into host dirs by
  hand: the script translates frontmatter per host, composes each host's global instructions and prunes removed v1 names.
- **New skill.** `skills/<name>/SKILL.md` with `name` and a trigger-focused `description`. Tests go in `skills/<name>/tests/`;
  never name one `*.test.mjs` (those gate every sync). Only built-in `subagent_type` values.
- **OpenCode.** Agents are auto-discovered from `~/.config/opencode/agents/`; `opencode.json` only sets `default_agent`.
  Never list agents under `instructions:` — it appends them to every agent's prompt.
- **Before push.** `bash scripts/gate.sh` exits 0 (hook: `git config core.hooksPath .githooks`).
