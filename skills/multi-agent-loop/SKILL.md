---
name: multi-agent-loop
description: Autonomous execution loop over dagRobin tasks. Use to start a project, resume interrupted work, continue after /compact, or review-only.
---

# Multi-Agent Loop — Infinite Execution System

## Review-Only routing

Review-only requests ("just review this") → jump straight to **Review-Only Mode**, skip the loop.

## Agents

| Role | Description | File |
|------|-------------|------|
| orchestrator | Pipeline coordinator, dispatches agents | agents/orchestrator.md |
| architect | Decisions only (not implementation) | agents/architect.md |
| project-manager | Reads PLAN.md, creates dagRobin tasks | agents/project-manager.md |
| builder | Implements tasks from dagRobin | agents/builder.md |
| qa-evaluator | Live testing, produces QA_REPORT.md | agents/qa-evaluator.md |
| code-reviewer | Spec compliance + quality review | agents/code-reviewer.md |
| summarizer-auditor | Audits `.claude/` ledgers once per Deep Audit pass (see §Deep Audit) | agents/summarizer-auditor.md |
| external worker | Optional autonomous coder for TYPE A batches | `hermes -z "<task>" --yolo` |

## Core Principles

1. **dagRobin is source of truth** — always prefer existing tasks over re-planning
2. **Execute, don't plan** — prefer implementation over analysis
3. **Architect is for decisions only** — not for implementation or task decomposition. And only for TYPE B (see below).
4. **TODOs must die** — resolve aggressively, escalate only real decisions
5. **Use `/compact` before gap detection**
6. **Plans are dumb-model contracts on first draft, not after** — the architect's PLAN.md must include an Executable Spec block per task (per `agents/architect.md`) so a model with zero conversation context can implement each task without asking. project-manager copies that block verbatim into `metadata.long-description`. No separate "simplification pass" exists; the contract is correct on first write or it is wrong.

## Execution Flow

### Phase 0 — Re-entry Protocol (every entry, no exceptions)

You may be a fresh iteration of `~/.claude/skills/multi-agent-loop/scripts/ralph.sh`, a post-`/compact` continuation, or a new session. Assume state exists on disk and **resume it** — never re-plan while state exists.

```
0. [ -f .claude/LOOP_ACTIVE ] || echo 0 > .claude/LOOP_ACTIVE   → arm the Stop gate (see §Turn Contract)
1. git status --porcelain      → uncommitted diff? That IS your current task. Finish + commit it first.
2. cat .claude/WATCHDOG.md     → workers with no verdict? Run the watchdog cycle on each.
3. dagRobin list               → IN_PROGRESS tasks with no live worker → NEW_ROUND them.
4. dagRobin ready               → tasks exist? dispatch builders (background, parallel per
   §Dispatch below).
5. dagRobin ready empty → plan exists? project-manager creates tasks from it : launch architect.
   Only if steps 1–3 each printed empty AND step 4 dispatched nothing AND step 5 created no new
   tasks → Phase 2 gap detection.
```

Skipping this and "starting fresh" is how projects end with "Diff pendente, nada commitado".

### Phase 2 — Gap Detection

Run when dagRobin is quiescent (§Infinite Loop) or execution stabilizes; run `/compact` first.

**Checks — each needs a command run this turn and its output quoted; a check with no output is
not done:**
- TODOs / "fake", "mock", "placeholder" / stub implementations
- Incomplete flows
- Missing error handling
- Missing validation
- Missing tests
- Lint/complexity-gate failures (the stack's lint command exits non-zero)
- Unused or dead code

### Deep Audit — see [reference/deep-audit.md](reference/deep-audit.md)

Runs once per loop run when quiescent and Phase 2 found no TYPE A gap. Finds what's excessive
(dead abstractions, legacy paths, duplicated representations) — Phase 2 only finds what's
missing. Its import filter is what keeps the loop finite.

### Gap Classification

| Type | Examples | Action |
|------|----------|--------|
| **TYPE A** — Builder-Fixable | Bugs, TODOs, missing logic, edge cases, ordering of independent work, naming, file layout — anything reversible in ≤1 commit | Create dagRobin task, dispatch builder. Pick a reasonable default (existing pattern → lower blast radius → smaller diff → listed/alphabetical order) and proceed. |
| **TYPE B** — Requires Decision | A **one-way door**: reverting it costs more than one commit, or it introduces an external dependency / public API / data migration, and no existing repo pattern already covers it | Launch architect — see [reference/architect-decision-protocol.md](reference/architect-decision-protocol.md) |
| **TYPE C** — Human Required | API keys, infra setup, secrets, manual QA, credentials for remote pushes, product decisions only the user can own | Record explicitly. Creates no dagRobin task. |

**Half-fixes are TYPE A, not "deferred improvements".** A pragmatic interim choice that leaves a
known-wrong behavior (a clamp that neuters a limit, an invariant with a carve-out, a value you
know should be derived from the real source) is a dagRobin task with the correct fix as its
acceptance criterion. A claim only earns `.claude/IMPROVEMENTS.md` with a **repro** — no repro,
i.e. no concrete input/state that breaks — go there; a repro makes it a dagRobin task instead.

### Phase 3 — Evaluation

After execution batch completes:

**qa-evaluator** (Complex projects): live application testing, produces `.claude/QA_REPORT.md`.
**code-reviewer** (All projects): spec compliance + quality review, scored verdict.

PASS is whatever each subagent's own threshold says — see `agents/qa-evaluator.md` and
`agents/code-reviewer.md`; this skill does not define a separate bar. FAIL on either → fix loop.

## Review-Only Mode

Entry point when the ask is "just review" — iterative review + auto-fix until clean.

```
REVIEW_LOOP:
  1. Determine <base>: the PR base, the branch point, or an explicit ref the user named.
  2. Run the `pr-review-pipeline` skill with `--deep` over `git diff <base>...HEAD`.
  3. Apply §Review Loop Termination.
  4. No claims with a repro → Report. STOP.
  5. Claims remain:
     a. Create dagRobin tasks (TYPE A batch)
     b. Dispatch builders (parallel, background)
     c. Watchdog cycle until every worker is *reaped*
     d. GOTO 1 (re-review)
```

Rules for this mode:
- Auto-fix iteratively until no claims with a repro remain
- Skip Phase 0 steps 4–5 (dagRobin-driven dispatch/planning), Phase 2 gap detection, and TYPE B
  architect escalation entirely
- On round 1 only, run `repo-audit` in **DIFF mode** over the same `<base>...HEAD` — it catches
  what a diff review misses: abstractions the change introduces that pay no rent. Import per
  [reference/deep-audit.md](reference/deep-audit.md)'s filter, substituting `pre_existing: false`
  for the dagRobin-empty trigger; route the rest the same way. Do not re-run it on later rounds.
- Skip the Hard Stop checklist (review-only is simpler)
- Max 3 review rounds (prevent infinite loops; if still broken on round 4, escalate)

## Infinite Loop

**Quiescent** — all three hold, each verified by command output quoted this turn:
`dagRobin list --format json` returns `[]`; `.claude/WATCHDOG.md` has no line ending
`STILL_WORKING`; `git status --porcelain` is empty. Exit only when quiescent and every Hard Stop
Condition bullet holds.

```
LOOP:
  1. dagRobin ready
  2. Dispatch pending tasks (builders parallel, background)
  3. Watchdog cycle per worker until every one is *reaped* to REVIEW/NEW_ROUND/STUCK — §Watchdog Protocol
  4. Run QA + code review; keep only claims with a repro
  5. Fix claims with a repro (dagRobin tasks); apply §Review Loop Termination to the rest
  6. Not quiescent yet → GOTO 1
  7. Quiescent → /compact
  8. Gap detection (Phase 2)
  9. Classify:
     - TYPE A → dispatch builder → GOTO 1
     - TYPE B → launch architect → GOTO 1
     - TYPE C → record and skip
 10. Hard Stop Condition holds (every bullet verified this turn, output quoted) → exit
     else → GOTO 1
```

## Dispatch (Parallelization Decisor)

Parallelize by default; worktrees are an optimization, not a prerequisite. For each group of
ready tasks {T1..Tn}:

1. Compute the dependency graph from dagRobin `uses` fields; group into topological layers
   L1, L2, ... where no task in Lk uses a task in Lj with j < k.
2. Within each layer, run `dagRobin conflicts`. Disjoint `files` → dispatch ALL in background
   (default), each subagent in the main tree; the orchestrator merges results in topological
   order. Overlapping `files` → split by file ownership, dispatch each group in parallel,
   serialize within the group.
3. Do not dispatch L(k+1) until Lk is done — supervise via §Watchdog Protocol (poll, inspect,
   decide) instead of waiting idle; keep doing useful work (next layer's conflict analysis, gap
   reads, drafting the next Executable Spec) while workers run.
4. Use a worktree (`git worktree add`) only when tasks conflict on files or the user asks for
   one — otherwise dispatch in the main tree.
5. A task runs foreground only when its result blocks the orchestrator's next decision (e.g. its
   own gap fix, where progress depends on the result).

## Watchdog Protocol (background workers)

Background dispatch is fire-and-forget only for *starting*. Every stopped worker is **reaped**:
read `dagRobin get <task-id>`, then `rtk git status` and `rtk git diff --stat` **inside the
worker's recorded worktree path**, then record one verdict below in `.claude/WATCHDOG.md`.

**At dispatch, append one line to `.claude/WATCHDOG.md`** (create if missing): task id, worker
handle (agent id, or the PID from `hermes ... & echo $!`), worktree path if not the main tree,
`git rev-parse HEAD`. First line of the file records `<base>` = the loop-start HEAD. This ledger
is the only watchdog state that survives `/compact`.

Cycles trigger on the worker's completion notification or a `Monitor` until-loop on its handle —
see §Dispatch step 3 for staying busy while it runs.

| Decision | When |
|----------|------|
| `STILL_WORKING` | Worker alive — that's enough; it may be compiling or testing. Wait for the next cycle. |
| `REVIEW` | Worker stopped **and** every acceptance criterion in the task's `metadata.long-description` is met by the diff **and** the gate is **green** (test runner, typechecker/build, and linter each exit 0, per the stack's rule file; `tsc --noEmit`/`cargo check`/`mypy`/`go vet` catch what the test runner doesn't) → Phase 3, then `dagRobin update <task-id> --status done`. |
| `NEW_ROUND` | Worker stopped below that bar. Re-dispatch on the **current** repo state — never reset or discard prior work. Tell it: *new round, previous process stopped, inspect the current diff, assume nothing about it, stay in scope.* |
| `STUCK` | Two consecutive ledger lines with identical HEAD and `diff --stat`. Kill it (`TaskStop`, or `kill <pid>`) and re-dispatch narrower. |

**Default worker = your own host's native agent mechanism** (Claude Code `Agent` subagents,
Hermes's own subagents, etc). External worker option (hermes, Claude-Code-only): see
[reference/external-workers.md](reference/external-workers.md).

## Review Loop Termination

Review output is a set of claims. A claim only becomes a dagRobin task when it has a **repro**
(§Gap Classification). Claims you disproved (callers/types/tests/invariants make it impossible)
go to `.claude/FALSE_POSITIVES.md` with the proof — every later review round reads that file
first and drops what's already rejected there. Without the ledger the loop rediscovers the same
non-bug forever.

Do not manufacture defects to keep the loop alive. "Another possible concern" is not a defect.
The `agents/orchestrator.md` max-3-iterations bound still applies.

## Turn Contract

The loop is not "GOTO 1" in your head — it is the driver re-invoking you. Your turn is one
iteration. A turn may end in exactly three ways:

| Ending | When | Print |
|---|---|---|
| **Iteration done** | You committed a unit of work (or dispatched + recorded workers in WATCHDOG.md). More remains. | Nothing special. Driver re-invokes. |
| **Hard stop** | Every line of §Hard Stop Condition verified this turn, with command output. | `<promise>HARD_STOP</promise>` as the last line. |
| **Blocked** | Only TYPE C remains, each one listed with why no agent can decide it. | `<promise>BLOCKED_TYPE_C</promise>` as the last line. |

A valid ending commits a unit of work, dispatches a worker and records it in WATCHDOG.md, or
prints a verified promise. A progress report, a plan, or an uncommitted diff is none of those —
you are mid-iteration, keep going. The gate allows a stop only when: the repo is quiescent and
the promise is `HARD_STOP`; the promise is `BLOCKED_TYPE_C` and the repo is quiescent too (TYPE C
never creates a dagRobin task, so quiescent already holds when only TYPE C remains); or
`.claude/WATCHDOG.md`'s last line ends `STILL_WORKING` and the tree is clean (a live worker is
running, nothing else to dispatch this turn).

**Arm the gate on entry:** `echo 0 > .claude/LOOP_ACTIVE` as the first command of Phase 0 (skip
if it already exists — it holds the iteration counter). The gate disarms itself on a verified
promise. Never delete it by hand to escape.

**Waiting on external work** (CI, a deploy, a long `hermes` worker with nothing else to
dispatch): call `ScheduleWakeup` with a delay matched to that work, then end the iteration — the
live-worker allowance above lets the gate release this turn, and the wakeup re-invokes you.

## Drivers

Enforced by something outside the model — see [reference/drivers.md](reference/drivers.md) for
the Stop hook, `ScheduleWakeup` and `ralph.sh` layers. Safety valve for all layers: `RALPH_MAX`
iterations (default 50) releases the loop.

## Hard Stop Condition

Stop ONLY when ALL hold, each observed this turn:
- The repo is quiescent (§Infinite Loop).
- No TYPE A gaps remain: the Phase 2 checklist ran this iteration and every one of its checks
  printed empty/zero, output quoted this turn.
- No TYPE B decisions pending: every gap classified this run is either a closed dagRobin task or
  on the TYPE C list — none left unclassified.
- Only TYPE C remains (explicitly recorded).
- A fresh-eyes `pr-review-pipeline --deep` pass over the full diff (`git diff <base>...HEAD`)
  came back clean and *green* (§Watchdog Protocol). `--deep` is the part that makes it
  fresh-eyes: it dispatches reviewers into their own context, where the default path applies the
  rubric on this thread and inherits everything this thread already believes.
- `repo-audit` ran once this run (`.claude/AUDIT_RAN` exists, `.claude/AUDIT.yaml` written) and
  every finding passing [reference/deep-audit.md](reference/deep-audit.md)'s import filter is
  either done or routed to FALSE_POSITIVES / IMPROVEMENTS / TYPE C.

Once every bullet holds, write the closing report from
[reference/final-output.md](reference/final-output.md) and print the promise from §Turn Contract.
