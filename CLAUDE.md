# RTK (Rust Token Killer)

A PreToolUse hook rewrites Bash commands to `rtk` automatically (`git status` → `rtk git status`); don't add the prefix by hand. RTK also provides standalone commands the hook cannot derive from a plain command: `rtk read <file>`, `rtk grep <pattern>`, `rtk ls <path>`, `rtk find <pattern>`, `rtk err <cmd>`, `rtk summary <cmd>`, `rtk log <file>`, `rtk json <file>`, `rtk proxy <cmd>` (unfiltered output, for debugging), `rtk gain` (savings analytics).

## Task Management — dagRobin Only

- Track tasks, sprints and progress in dagRobin, not the harness's built-in task tools — dagRobin is the shared database every pipeline agent reads, so work tracked anywhere else is invisible to them.
- Run `dagRobin init` once in the project root; `.dagrobin/db` is found by walk-up, so no `-d` flag. Override with `-d` or `$DAGROBIN_DB` only when you deliberately want a different database.

## OpenCode Multi-Agent Configuration

Agents are **auto-discovered**, not registered. OpenCode reads every markdown file in `~/.config/opencode/agents/`, takes the agent name from the filename, and reads `mode:` from that file's frontmatter.

- `opencode.json` stays minimal — it only sets `default_agent`. Do **not** list agents under `instructions:`: that key appends files to the system prompt of *every* agent, so all personas bleed into each other and subagents lose their identity.
- Adding or removing `agents/<name>.md` needs no config change. Just re-run the sync.
- **Never copy `agents/*.md` raw into an OpenCode config dir** (no `cp -r`, no zip). The source frontmatter is Claude Code native (`tools: Read, Edit, ...` CSV) and OpenCode rejects it with `Expected object | undefined, got "Read, Write, ..."`. Only `scripts/sync-skills.sh` produces a valid OpenCode copy — it translates the `tools:` CSV into `permission:` denials, drops `model:` (Claude's bare `sonnet` is not a valid OpenCode `provider/model` id), and **preserves `mode:`**, which OpenCode needs to tell a primary agent from a subagent.
- Run `bash scripts/sync-skills.sh` to sync agents, skills, rules, resources and `opencode.json`. It syncs to Claude Code, OpenCode, Codex, Hermes and Pi (`~/.pi/agent/`); destinations are fixed inside the script. Use `--status` for a dry run, `--only=opencode` to limit the target, and `bash scripts/test-sync-skills.sh` to verify changes to the sync itself.

## Voice — ADHD-Friendly
User has ADHD. Reply in cave-man + ADHD-friendly style. Always.

1. Lead with the answer or the next action. No intro.
2. Short sentences. Fragments OK.
3. Drop articles (the, a, an), filler words, politeness fluff.
4. No pleasantries, no filler, no cuteness.
5. Numbered steps when count > 1. Keep lists short; split a long procedure into stages.
6. End with ONE concrete next action.
7. Code, commands, technical terms stay normal.
