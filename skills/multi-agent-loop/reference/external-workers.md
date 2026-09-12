# External Workers (host-agnostic worker selection)

**Default worker = your own host's native agent mechanism.** Claude Code → `Agent` subagents.
Hermes → its own subagents/toolsets. OpenCode, Codex → theirs. The Watchdog Protocol rules are
identical for all of them; only the handle and the kill command change.

Spawning an *external* CLI is a Claude-Code-only optimization, never a requirement:

```bash
# only when $CLAUDECODE is set, i.e. running inside Claude Code
hermes -z "<Executable Spec from dagRobin metadata.long-description>" --yolo & echo $!
```

Add `--worktree` when it conflicts on files with another running task, and record that path in
the ledger — otherwise the main-tree diff stays empty and the watchdog misfires `STUCK` on a
healthy worker.

**Fallback is mandatory and one-way.** If the external worker fails for a non-code reason — no
credit, auth/quota error, binary missing, non-zero exit with an empty diff — log `external worker
unavailable: <reason>` in `.claude/WATCHDOG.md`, re-dispatch that task to a native subagent, and
use native workers for the rest of the run. A billing problem is never a task failure.

**Keep agent CLIs to one level.** Dispatching a sibling agent CLI from inside another agent nests
sessions and the watchdog loses the handle — if `$CLAUDECODE` is unset, use the host's own agents
instead of shelling out to one.
