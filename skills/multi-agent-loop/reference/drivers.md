# Drivers (Ralph)

The loop is enforced by something outside the model. Three layers, all shipped in
`~/.claude/skills/multi-agent-loop/scripts/`:

| Layer | Mechanism | When it applies |
|---|---|---|
| **Stop hook** `stop-gate.sh` | `hooks.Stop` in `~/.claude/settings.json`. Every turn end runs it; while `.claude/LOOP_ACTIVE` exists it returns `decision: block` unless the promise is verified. Claude cannot end the turn. | Interactive Claude Code sessions — the default. |
| **`ScheduleWakeup`** | Skill self-schedules a wakeup when waiting on external work. | Inside Claude Code, complements the hook. |
| **`ralph.sh`** | `while :; do claude -p PROMPT; done` from a plain shell. Fresh context per iteration, logs to `.claude/RALPH.md`, exits on verified promise / TYPE C / `--max`. | Headless, CI, `--worker hermes`, or any host without Stop hooks. |

```bash
~/.claude/skills/multi-agent-loop/scripts/ralph.sh --max 30   # run from a plain shell, outside any agent session
```
