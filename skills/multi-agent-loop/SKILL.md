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
3. **Architect is for decisions only** — not for implementation or task decomposition
4. **TODOs must die** — resolve aggressively, escalate only real decisions
5. **Use `/compact` before gap detection** — reduces context, ensures clean state

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
| **TYPE A** — Builder-Fixable | Bugs, TODOs, missing logic, edge cases | Create dagRobin task, dispatch builder |
| **TYPE B** — Requires Decision | Multiple valid approaches, tradeoffs | Launch architect with decision protocol |
| **TYPE C** — Human Required | API keys, infra setup, secrets, manual QA | Record explicitly, DO NOT create tasks |

### Architect Decision Protocol

When TYPE B gap is detected, launch architect with:

```
## Decision Request: <gap title>

## Context
<why this requires a decision>

## Options to Evaluate
<generate 5-7 internal options, evaluate on: feasibility, effectiveness, impact, risk, alignment>

## Output Required
Option 1: [Name]
- Description
- Why selected
- Key benefits (3)
- Implementation considerations
- Next steps

Option 2: [Name]
- Same structure
```

**After decision:**
- Convert decision into tasks
- Send to project-manager
- Import to dagRobin
- Continue loop

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

- Run multiple builders in parallel
- Use worktrees for isolation (orchestrator handles)
- Avoid file conflicts (check `uses` dependencies)
- Respect dependencies strictly

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
```

## Important Rules

1. **Never stop early** — complete the loop until hard stop condition
2. **Never create tasks for TYPE C** — record only
3. **Architect escalation** — only for real tradeoffs, not for implementation questions
4. **dagRobin isolation** — use `-d` flag for local project, inherit by default
5. **Compact before detection** — always run `/compact` before gap analysis to reduce context