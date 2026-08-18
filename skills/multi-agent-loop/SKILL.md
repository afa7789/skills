---
name: multi-agent-loop
description: Infinite multi-agent execution system. dagRobin-first, gap detection, decision escalation. Coordinates orchestrator/architect/builder/qa/code-reviewer/summarizer agents via conversation context. Use when starting new projects or continuing interrupted work.
---

# Multi-Agent Loop — Infinite Execution System

dagRobin is the primary source of truth. Continuous execution loop with gap detection and escalation.

## When to Use

- Starting new projects (triggers orchestrator)
- Continuing interrupted work (checks dagRobin)
- After manual `/compact` to continue execution

## Agents

| Role | Description | File |
|------|-------------|------|
| orchestrator | Pipeline coordinator, dispatches agents | agents/orchestrator.md |
| architect | Decisions only (not implementation) | agents/architect.md |
| project-manager | Reads PLAN.md, creates dagRobin tasks | agents/project-manager.md |
| builder | Implements tasks from dagRobin | agents/builder.md |
| qa-evaluator | Live testing, produces QA_REPORT.md | agents/qa-evaluator.md |
| code-reviewer | Spec compliance + quality review | agents/code-reviewer.md |
| summarizer-auditor | Audit .claude/ folder | agents/summarizer-auditor.md |

## Core Principles

1. **dagRobin is source of truth** — always prefer existing tasks over re-planning
2. **Execute, don't plan** — prefer implementation over analysis
3. **Read existing code before deciding** — if an algorithm/implementation already exists, inspect it and adapt; do NOT redesign from scratch or escalate decisions about something that's already written. "Pronto e ajustar depois" > "decidir do zero".
4. **Reversibility test before escalating** — if the decision can be reverted in ≤1 commit, DO NOT escalate. Pick a reasonable default and proceed. Only escalate truly irreversible or expensive-to-undo choices.
5. **Order-independent work is auto-decided** — when ordering, naming, or sequencing doesn't change the outcome (e.g. order of independent patches/commits), pick alphabetical/listed order and execute. Never ask the user "qual primeiro?" for fungible work.
6. **Architect is for decisions only** — not for implementation or task decomposition. And only for TYPE B (see below).
7. **TODOs must die** — resolve aggressively, escalate only real decisions
8. **Use `/compact` before gap detection** — reduces context, ensures clean state
9. **Plans are dumb-model contracts on first draft, not after** — the architect's PLAN.md must include an Executable Spec block per task (per `agents/architect.md`) so a model with zero conversation context can implement each task without asking. project-manager copies that block verbatim into `metadata.long-description`. No separate "simplification pass" exists; the contract is correct on first write or it is wrong.

## Execution Flow

### Phase 1 — Start from dagRobin

```
1. dagRobin ready → check for pending tasks
2. If tasks exist → dispatch builders (parallel)
3. If empty → check if plan exists
   - Plan exists → project-manager creates tasks
   - No plan → launch architect
4. Respect dependencies, maximize parallelism
5. Continue until dagRobin is empty
```

### Phase 2 — Gap Detection (CRITICAL)

Run **AFTER** `/compact` when:
- dagRobin is empty, OR
- execution stabilizes (all tasks done)

**Explicit checks:**
- TODOs in code
- Stub implementations
- "fake", "mock", "placeholder"
- Incomplete flows
- Missing error handling
- Missing validation
- Missing tests
- Unused or dead code

**Ask:**
- "What is still missing?"
- "Is any TODO or partial implementation left?"
- "Was something intentionally skipped?"

### Gap Classification

| Type | Examples | Action |
|------|----------|--------|
| **TYPE A** — Builder-Fixable | Bugs, TODOs, missing logic, edge cases, ordering of independent work, naming, file layout, anything reversible in ≤1 commit | Create dagRobin task, dispatch builder. Pick a reasonable default and proceed. |
| **TYPE B** — Requires Decision | Truly irreversible OR expensive-to-undo OR introduces external dependency / public API / data migration | Launch architect with decision protocol |
| **TYPE C** — Human Required | API keys, infra setup, secrets, manual QA, credentials for remote pushes | Record explicitly, DO NOT create tasks |

### Before Escalating to TYPE B — Mandatory Checks

Run these in order. If any answers "yes", it's TYPE A — execute, don't ask.

1. Does an existing implementation/algorithm already cover this? → Read it, adapt, proceed.
2. Can the choice be reverted in ≤1 commit? → Pick default, proceed.
3. Are the options functionally equivalent (only ordering/naming differ)? → Pick alphabetical/listed order, proceed.
4. Is the user likely to say "tanto faz"? → It's TYPE A. Pick and proceed.

Only after all four are "no" — escalate.

### Architect Decision Protocol

When a TYPE B gap is detected, launch architect with the prompt below. The architect **takes the decision itself** — no user round-trip, no two-options menu. Possible improvements are recorded for the end-of-flow report instead of blocking execution.

```
# Instructions
You are an expert technical architect for this codebase.
Your task is to make a decision and produce executable tasks. You do NOT ask the user — you decide.

# Process

## Step 1 — Inspect existing patterns FIRST (mandatory)
Before generating options, scan the repo for relevant existing patterns:
- Similar modules, algorithms, abstractions already in use
- Conventions documented in CLAUDE.md / rules/
- Vendored deps or sibling features that solve adjacent problems

If an existing pattern fits (even partially), bias the decision toward extending/adapting it rather than introducing a new approach.

## Step 2 — Generate Options (silent)
Internally generate 5–7 distinct, high-quality options. Each must be:
- Clear, specific, and actionable
- Aligned with the codebase's existing patterns and conventions
- Feasible within realistic constraints
- Optimized for the stated goal

Do NOT show these to the user.

## Step 3 — Evaluate (silent)
Score each option on:
- Feasibility — can it ship now?
- Effectiveness — does it solve the core problem?
- Impact — positive outcome
- Risk — downsides, blast radius, reversibility
- Alignment — fit with existing patterns (PRIMARY tiebreaker)

## Step 4 — Decide
Pick ONE option. Tiebreaker order:
1. Reuses existing pattern in the codebase
2. Lower blast radius / more reversible
3. Smaller diff / less new surface area
4. Listed/alphabetical order

Do NOT present 2 options to the user. Decide.

# Output Format

## Decision: <Name>
**Chosen approach:** <one paragraph>

**Why this fits existing patterns:** <reference the specific module/file/convention being reused>

**Tasks (ready for project-manager → dagRobin):**
- [ ] <task 1, with file paths and acceptance criteria>
- [ ] <task 2 ...>

**Possible Improvements (deferred — surface at end of flow):**
- <improvement 1: what would be better in a greenfield context, why we didn't do it now>
- <improvement 2 ...>

# Problem/Task Details
<gap description, context, constraints>

Begin analysis now. Decide. Produce tasks. Do not ask.
```

**After decision:**
- Convert tasks into dagRobin entries via project-manager
- Append "Possible Improvements" to `.claude/IMPROVEMENTS.md` (create if missing)
- Continue loop — do NOT pause for user confirmation
- Surface improvements only in the **Final Output** section (Hard Stop)

### Phase 3 — Evaluation

After execution batch completes:

**qa-evaluator** (Complex projects):
- Live application testing
- Produces `.claude/QA_REPORT.md`
- PASS → continue / FAIL → fix loop

**code-reviewer** (All projects):
- Spec compliance check
- Quality review
- Scored verdict

## Infinite Loop

```
LOOP:
  1. dagRobin ready
  2. Execute pending tasks (builders parallel)
  3. Run QA + code review
  4. Fix failures (create dagRobin tasks)
  5. Check dagRobin
  6. If empty → /compact
  7. Gap detection
  8. Classify:
     - TYPE A → dispatch builder
     - TYPE B → launch architect
     - TYPE C → record and skip
  9. GOTO 1
```

## Concurrency Rules

**ALWAYS parallelize. Worktrees are an optimization, not a prerequisite.**

The default dispatch is `run_in_background: true` for every ready task. Two
tasks are parallel iff neither's `file` appears in the other's `uses` —
otherwise they form a serial chain. Anything else is parallel.

- **Background by default.** Dispatch every ready task in background with
  its own subagent. Don't serial-then-batch; batch-then-dispatch.
- **Worktree isolation is opt-in, not required.** Use `git worktree add` only
  when (a) tasks touch the same file with conflicting diffs, or (b) the user
  explicitly asks. For independent files, run them backgrounded in the main
  tree — subagents each get their own context and the orchestrator merges
  in topological order.
- **Avoid file conflicts (check `uses` dependencies).** If two tasks edit the
  same `file`, run them sequentially in the same hand. Track this via the
  `dagRobin conflicts` subcommand before dispatching.
- **Respect dependencies strictly.** If B `uses` A, B cannot start until A
  is `done` in dagRobin.
- **Single-task fallback only when truly serial.** A task is only run
  foreground when its result blocks the orchestrator's next decision
  (e.g. executing our own gap fix where progress depends on the result).

## Parallelization Decisor (use before any dispatch)

```
For each group of ready tasks {T1, T2, ..., Tn}:

  1. Compute the dependency graph from dagRobin `uses` fields.
  2. Group into topological layers L1, L2, ... where no task in Lk uses a
     task in Lj with j < k.
  3. Within each layer:
       - If all tasks have disjoint `files` (run `dagRobin conflicts`):
         dispatch ALL in background (default). Each subagent works in the
         main tree; orchestrator collects results and merges any conflicts
         via the methodology in agents/orchestrator.md.
       - Else: split by file ownership, dispatch each file-group in
         parallel and serialize within the group.
  4. Wait for layer Lk to complete before dispatching L(k+1).
```

This applies whether worktrees exist or not. The orchestrator NEVER waits
for a background task to finish — only `dagRobin ready` polls.

## Hard Stop Condition

Stop ONLY when:
- No TYPE A gaps remain
- No TYPE B decisions pending
- Only TYPE C remains (explicitly recorded)

## Final Output

```markdown
## Completed
- [list of completed features]

## Remaining Gaps
TYPE A: none
TYPE B: none
TYPE C:
  - [ ] <human-required item>

## Possible Improvements (deferred during execution)
- <pulled from .claude/IMPROVEMENTS.md — decisions taken pragmatically that could be revisited>
- <each item: what was chosen, what would be ideal, rough effort to migrate>
```

## Important Rules

1. **Never stop early** — complete the loop until hard stop condition
2. **Never create tasks for TYPE C** — record only
3. **Architect escalation** — only for real tradeoffs, not for implementation questions. Order, naming, and reversible choices are NEVER escalated.
4. **dagRobin isolation** — use `-d` flag for local project, inherit by default
5. **Compact before detection** — always run `/compact` before gap analysis to reduce context
6. **Parallelize or it didn't happen** — if a layer has >1 ready task and you
   dispatched them sequentially in foreground, that is a process violation.
   Cancel and re-dispatch them in background. Exception: same-file edits,
   which must serialize within the orchestrator's hand.
7. **Don't ask the user for fungible decisions** — if you catch yourself writing "Quer que eu comece pelas patches (por qual?)" or "qual primeiro?" for independent work, STOP. Pick the listed order and execute. The user will say "tanto faz" anyway.
8. **Inspect before deciding** — if a similar algorithm/component already exists in the repo (or in a vendored dep), read it first. Adapting working code beats greenfield decision-making.