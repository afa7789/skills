# Prompt-asset repository

Skills, agents and rules for Claude Code and five sibling hosts. The global rules in
`~/.claude/CLAUDE.md` and `~/.claude/rules/` apply here too and are not repeated below.

## OpenCode Multi-Agent Configuration

Agents are **auto-discovered**, not registered. OpenCode reads every markdown file in `~/.config/opencode/agents/`, takes the agent name from the filename, and reads `mode:` from that file's frontmatter.

- `opencode.json` stays minimal — it only sets `default_agent`. Do **not** list agents under `instructions:`: that key appends files to the system prompt of *every* agent, so all personas bleed into each other and subagents lose their identity.
- Adding or removing `agents/<name>.md` needs no config change. Just re-run the sync.
- **Never copy `agents/*.md` raw into an OpenCode config dir** (no `cp -r`, no zip). The source frontmatter is Claude Code native (`tools: Read, Edit, ...` CSV) and OpenCode rejects it with `Expected object | undefined, got "Read, Write, ..."`. Only `scripts/sync-skills.sh` produces a valid OpenCode copy — it translates the `tools:` CSV into `permission:` denials, drops `model:` (Claude's bare `sonnet` is not a valid OpenCode `provider/model` id), and **preserves `mode:`**, which OpenCode needs to tell a primary agent from a subagent.
- Run `bash scripts/sync-skills.sh` to sync agents, skills, rules, resources and `opencode.json`. It syncs to Claude Code, OpenCode, Codex, Hermes, Pi (`~/.pi/agent/`) and OMP (`~/.omp/agent/`); destinations are fixed inside the script. Use `--status` for a dry run, `--only=opencode` to limit the target, and `bash scripts/test-sync-skills.sh` to verify changes to the sync itself.
