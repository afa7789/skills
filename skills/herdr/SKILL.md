---
name: herdr
description: "Control Herdr, a terminal multiplexer for coding agents. Use only when the user explicitly mentions Herdr or asks to use Herdr to inspect or control panes, tabs, workspaces, commands, or another agent. Do not use merely because a task could benefit from a background terminal, delegation, or parallel work. Requires HERDR_ENV=1."
---

# Herdr

Herdr organizes workspaces, tabs, panes, and recognized coding agents. The `herdr` CLI in `PATH` talks to the current session. Run `herdr --skill` for the full reference.

## Gate

Before any control command:

```bash
test "${HERDR_ENV:-}" = 1
```

If it fails, say you are not inside Herdr and stop. Never control the focused session from outside Herdr.

## Discover

Learn syntax from the installed binary: `herdr --help`, then a group with no subcommand — `herdr agent`, `herdr pane`, `herdr workspace`, `herdr tab`, `herdr worktree`, `herdr terminal`, `herdr notification`, `herdr integration`, `herdr session`, `herdr machine`.

Never run bare `herdr` for discovery; it launches or attaches the TUI. Do not probe a mutating command by omitting arguments; some commands create with defaults. Parse IDs and state from JSON responses; never predict them.

Herdr injects `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_PANE_ID`. Prefer `--current` for the calling pane. Other commands may use UI focus, which can belong to another client.

Discover live state:

```bash
herdr workspace list
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
herdr pane current --current
```

IDs are opaque: workspace `w1`, tab `w1:t1`, pane `w1:p1`. Closed IDs are not reused. After `pane move`, use `.result.move_result.pane.pane_id`; the old ID works only for the moved process. IDs and live agent names are scoped to one server.

## Primitives

- Workspaces, tabs, panes: terminal topology.
- Pane commands: shells, tests, servers, raw input/output.
- Agent commands: recognized agents with `idle`, `working`, `blocked`, `done`, `unknown` states.

A pane exists without an agent. `agent start` needs an existing shell pane at its prompt; it never creates or moves layout. Agent names match `[a-z][a-z0-9_-]{0,31}` and follow the current occupant. `idle`/`done` mean ready for input, not proof no dialog or background work exists. `blocked` means an approval or question UI. `unknown` means unclassified.

## Coordinate an agent

Default to a sibling pane in the current tab and cwd. Do not create a workspace, tab, worktree, or different cwd unless asked.

```bash
herdr pane layout --pane "$HERDR_PANE_ID"
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr agent start reviewer --kind codex --pane <pane-id> -- <args>
herdr agent prompt reviewer "Review the current diff." --wait --timeout 120000
herdr agent get reviewer
herdr agent read reviewer --source recent-unwrapped --lines 120
herdr agent send-keys reviewer esc
```

Split right when wide, down when narrow or tall. Read the new pane ID from `.result.pane.pane_id`. Use the requested agent kind; run `herdr agent` for supported kinds. `--wait` waits for the first settled state; use `--until` only for a state-specific wait. If a prompt times out or returns `blocked`, inspect before sending more input; do not blindly retry. Ask the user before answering an approval dialog.

## Run a command

```bash
herdr pane split --current --direction right --cwd "$PWD" --no-focus
herdr pane run <pane-id> "just test"
herdr pane wait-output <pane-id> --match "test result" --timeout 120000
herdr pane read <pane-id> --source recent-unwrapped --lines 120
```

`pane run` queues input; success is admission, not execution. Read sources: `visible` (viewport), `recent` (wrapped), `recent-unwrapped` (joined wraps, best for logs), `detection` (agent-detection snapshot). Use `--format ansi` only when styling is evidence. Alternate-screen rows may not be in scrollback; for long agent output, ask the agent to write a temp file and read that path.

## Remote machines

Use the same global prefix for every command: `herdr --machine <label-or-id> agent list`. Local IDs and `--current` do not identify remote panes. `--machine` cannot combine with `--session` or `--remote`. Only add/remove/enable/disable profiles when asked; `machine reconnect` needs the user to finish SSH auth.

## Safety

- Use `--no-focus` for background work; keep user focus unless asked.
- Use `--current`, explicit pane IDs, or unique agent names. Ignore another client's focus.
- Do not close workspaces, tabs, panes, or sessions you did not create unless asked.
- Use `--trust-repository` only after the user verified the repo.
- Check `herdr status` after updates before relying on new server features.
- Never run `herdr server stop` from an active session unless explicitly asked. Never kill the main Herdr process.
- CLI server errors are JSON on stderr, exit 1; syntax errors exit 2.
