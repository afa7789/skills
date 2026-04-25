# Global Agent Rules

## Git
- Never amend commits. Always create a new commit.
- Use commit messages exactly as specified by the user, verbatim.
- Never add `Co-Authored-By` or "Generated with Claude Code" to commits, PRs, or any content.
- Never push without explicit request.

## Task Management — dagRobin Only
- **NEVER** use built-in TaskCreate, TaskUpdate, TaskList, or TaskGet tools. They are forbidden.
- ALL task tracking, sprint management, and progress tracking MUST use **dagRobin** exclusively.
- Run `dagRobin init` in the project root before first use. This creates `.dagrobin/db` which is auto-discovered by walk-up (like git finds `.git/`). No `-d` flag needed — subagents in any subdirectory automatically find the correct project database.
- If you need explicit control: `$DAGROBIN_DB` env var or `-d` flag override the walk-up.
- Use `dagRobin which-db` to verify which database is being used.

## Workflow
- Enter plan mode for any non-trivial task (3+ steps or architectural decisions). If something goes wrong, stop and re-plan.
- Use subagents for research, exploration, and parallel analysis. One focused task per subagent.
- Never mark a task complete without proving it works (run tests, lint, or equivalent).
- When given a bug report, fix it autonomously — don't ask for steps to reproduce if the report is clear.
- After any correction, capture the lesson in `tasks/lessons.md` so it isn't repeated.

## Core Principles
- **Simplicity first**: make every change as simple as possible. Minimal code impact.
- **No laziness**: find root causes. No temporary fixes. Senior developer standards.
- **Minimal impact**: only touch what is necessary for the task. Don't refactor, add comments, or clean up surrounding code unless asked.
- **Prove it works**: don't claim something is done without running the relevant test or verification.

## After Task Completion
1. Run the project's test suite to ensure nothing is broken.
2. Run the project's linter to check for warnings.
3. If a `.claude/PLAN.md` exists and the task corresponds to a TODO item, mark it completed with date and brief note.

## Browser Automation
When tasks require web interaction, UI testing, or browser control:
- **browser-use** (`browser-use/browser-use`) — Python, full browser control. Best for: UX walks, form interaction, multi-step flows.
- **Lightpanda** (`lightpanda-io/browser`) — Headless, Zig-based. Best for: CI pipelines, high-performance scraping.
- **page-agent** (`alibaba/page-agent`) — In-page JS agent. Best for: interacting with already-open pages.

@RTK.md
