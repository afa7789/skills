# Process Improvement Suggestions

Concrete improvements to the Spec-Driven AI pipeline, ordered by expected impact.

---

## 1. Add "Step 0: Validate the Problem"

The pipeline starts with "brain-dump all ideas." There is no explicit step to validate that the problem is worth solving.

**Add before Step 1:** A lightweight validation gate. Who is the user? What problem do they have? Can you find 3 people who would use this? This prevents building well-specified solutions to problems nobody has.

**Implementation:** Add a validation template to the planner skill that asks 3 questions before proceeding: (1) Who specifically will use this? (2) What are they doing today instead? (3) Why would they switch?

---

## 2. Formalize the Estimator as a Go/No-Go Gate

The estimator skill produces cost estimates, but there is no explicit threshold or decision point in the orchestrator that checks the estimate before proceeding.

**Change:** Add a step to `orchestrator/SKILL.md` between "Create Task Structure" and "Start the Build Loop" that runs the estimator, presents the cost to the user, and requires explicit approval. Make the budget-aware loop an enforced part of the pipeline rather than an optional step.

**Files to modify:**
- `orchestrator/SKILL.md` — add Step 3.5: "Run estimator, present cost, get go/no-go"
- `estimator/SKILL.md` — add a "quick estimate" mode that skips diff analysis for greenfield projects

---

## 3. Add a Design Review Checkpoint

The current Complex pipeline goes architect -> builder with no human checkpoint on the technical plan. The architect could make a bad stack choice or miss a constraint, and the builder would implement it faithfully.

**Change:** For Complex projects, add an explicit design review step where the human reviews `MULTI_AGENT_PLAN.md` before any implementation begins. The orchestrator should pause and present the plan summary to the user.

**Files to modify:**
- `orchestrator/SKILL.md` — add pause between architect and builder phases
- `architect/SKILL.md` — add a "handoff summary" section at the end of the plan

---

## 4. Version Sprint Contracts

Sprint contracts (`SPRINT_CONTRACT.md`) are overwritten each sprint. When the QA evaluator fails a build and the builder modifies testable behaviors, the original contract is lost.

**Change:** Name them `SPRINT_CONTRACT_001.md`, `SPRINT_CONTRACT_002.md`, etc. Or append a revision history section at the bottom. This gives you an audit trail of scope changes and helps identify scope creep.

**Files to modify:**
- `builder/SKILL.md` — change contract naming convention
- `qa-evaluator/SKILL.md` — read the latest numbered contract

---

## 5. QA-to-Planner Feedback Loop

When the QA evaluator repeatedly fails builds for the same category (e.g., Feature Completeness), that signal should propagate back to how the planner writes specs. Currently the pipeline is linear: planner -> ... -> qa-evaluator. There's no learning loop.

**Change:** After a project completes, the orchestrator runs a retrospective step that:
1. Reads all QA reports
2. Identifies patterns (e.g., "Feature Completeness failed 4 out of 6 sprints")
3. Writes a lessons-learned note that the planner reads in future projects

**Implementation:** Could be a new `retrospective` skill or an addition to `summarizer-auditor`.

---

## 6. Standardize Token Counting Methodology

The estimator skill has a placeholder format for token estimation (input tokens, reasoning tokens, output tokens) but no guidance on how to actually calculate these numbers.

**Change:** Add a methodology section to `estimator/SKILL.md`:
- Input tokens: count lines of code to be read x ~4 tokens/line
- Output tokens: estimate lines to be written x ~4 tokens/line
- Reasoning tokens: task complexity multiplier (Simple: 2x output, Medium: 5x output, Complex: 10x output)
- Add reference pricing for Claude models (Opus, Sonnet, Haiku) so estimates produce dollar amounts

Even rough heuristics make estimates consistent and comparable across projects.

---

## 7. Integration Tests for the Pipeline Itself

The skills system has a QA evaluator for the products it builds, but there is no test suite for the pipeline itself.

**Change:** Create a small reference project (e.g., "build a TODO CLI in Rust") that runs the full Complex pipeline end-to-end and verifies:
- Tasks were created in dagRobin
- All tasks reached "done" status
- QA evaluator produced a report
- Final build compiles and tests pass

This becomes a regression test for changes to any skill. Run it after modifying any SKILL.md.

---

## 8. Decouple Skills from `.claude/` Paths

Several skills hardcode paths like `.claude/PRODUCT_SPEC.md`, `.claude/tasks.yaml`, `.claude/SPRINT_CONTRACT.md`. The README mentions OpenCode compatibility, but the skills reference `.claude/` directly.

**Change:** Define a convention: use `$AGENT_DIR` or a config variable that defaults to `.claude/` but can be overridden. Or add a preamble to each skill: "Output directory: `.claude/` (or `.opencode/` if using OpenCode)."

**Files to modify:** All skills that reference `.claude/` paths (planner, builder, qa-evaluator, orchestrator, task-splitter, architect, summarizer-auditor).

---

## 9. Explicit DAG Review Step

dagRobin has a `graph` command, but the pipeline does not include an explicit step to review the dependency graph before execution.

**Change:** After Step 12 (organize tasks), add: "Run `dagRobin graph`, review the DAG, identify bottleneck tasks or overly long dependency chains." This is the equivalent of reviewing a Gantt chart before starting a sprint. Long sequential chains may indicate opportunities for parallelization.

**Files to modify:**
- `orchestrator/SKILL.md` — add graph review after task import

---

## 10. Structured Checkpoint-and-Resume Protocol

The orchestrator mentions "Resume After Tokens Ran Out" and has a cron example, but there's no structured checkpoint logic.

**Change:** When tokens run low mid-build, the orchestrator should:
1. Export dagRobin state
2. Write `.claude/RESUME.md` with: current context, in-progress work summary, next 3 tasks, any blockers
3. Mark in-progress tasks as "blocked" with metadata `reason=tokens_exhausted`
4. The next session reads `RESUME.md` and picks up cleanly

The cron approach (`*/30 * * * * cd /path && opencode "Check dagRobin"`) is a start but needs this structure to avoid losing context between sessions.

**Files to modify:**
- `orchestrator/SKILL.md` — add "checkpoint" protocol
- Consider a new `checkpoint/SKILL.md` that any agent can invoke when running low on context

---

## 11. Add a Brainstorming Skill

We jump straight from idea to spec (planner). There's no structured ideation phase to explore the problem space, consider alternative approaches, and validate designs before committing to a plan.

**Inspired by:** [obra/superpowers](https://github.com/obra/superpowers) brainstorming skill — a 9-step process: explore context, ask clarifying questions one at a time, propose 2-3 approaches with trade-offs, present design sections for approval, then write a design doc. No implementation until design is approved.

**What to build:** A `brainstorming` skill that:
1. Asks clarifying questions (one at a time, not a wall of questions)
2. Proposes 2-3 approaches with explicit trade-offs
3. Gets user approval on design sections incrementally
4. Produces a design document that feeds into the planner
5. Has a "visual companion" mode for UI/UX work (diagrams, wireframes)

**Why this matters:** The planner currently assumes you know what you want. Brainstorming catches bad assumptions and explores alternatives before the spec locks you in.

---

## 12. Add a Systematic Debugging Skill

We have no structured debugging process. When something breaks, the builder or senior-developer improvises. This leads to symptom-fixing instead of root cause analysis.

**Inspired by:** superpowers systematic-debugging — enforces: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.

**What to build:** A `debugger` skill with phases:
1. **Root Cause Investigation** — read errors, reproduce, gather evidence
2. **Pattern Analysis** — compare broken code with working code
3. **Hypothesis Testing** — test one variable at a time (not shotgun fixes)
4. **Implementation** — create a failing test first, then fix
5. **Defense in Depth** — add validation at multiple layers to prevent recurrence

**Red flags to enforce:** Stop after 3+ failed fix attempts and re-investigate. Never propose multiple changes simultaneously. Never say "try this and see if it works."

---

## 13. Add a Test-Driven Development Skill

Our builder and qa-evaluator test after implementation. There's no enforced test-first discipline.

**Inspired by:** superpowers test-driven-development — enforces the Iron Law: NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.

**What to build:** A `tdd` skill that the builder invokes per task:
1. **RED** — Write a failing test that defines the expected behavior
2. **GREEN** — Write the minimal code to make it pass
3. **REFACTOR** — Clean up without changing behavior, tests stay green

**Anti-patterns to flag:**
- Testing mock behavior instead of real behavior
- Adding test-only methods to production code
- Writing code first and tests after (delete and restart)
- Over-mocking without understanding what's being mocked

**Integration:** The builder skill should invoke TDD for each task. The qa-evaluator should verify the RED-GREEN-REFACTOR sequence in the git history.

---

## 14. Add a Verification Before Completion Discipline

We claim tasks are done without proving it. The qa-evaluator catches this at the sprint level, but individual task completion has no verification standard.

**Inspired by:** superpowers verification-before-completion — "Evidence must precede all completion claims."

**What to build:** A verification protocol embedded in the builder and orchestrator:
1. Identify the verification command (test, build, lint, manual check)
2. Execute it completely (not "it should work")
3. Examine the full output (not just exit code)
4. Confirm output supports the completion claim
5. Include evidence in the task completion message

**Warning signs to flag:** "should work," "probably passes," "seems fine," relying on a previous test run, claiming success without showing output.

**Implementation:** Add a verification checklist to `builder/SKILL.md` and a verification audit to `qa-evaluator/SKILL.md`.

---

## 15. Add Git Worktree Support

All our work happens on the current branch. There's no isolation between parallel tasks, and switching context means stashing or committing half-done work.

**Inspired by:** superpowers using-git-worktrees — creates isolated workspaces within the same repo.

**What to build:** A `worktree` skill or protocol in the orchestrator:
1. Create a worktree for each independent task or feature
2. Auto-detect and install dependencies in the new worktree
3. Run baseline verification tests before starting work
4. Clean up worktrees after merge

**Why this matters:** When the orchestrator dispatches parallel agents, each should work in its own worktree to avoid conflicts. This is especially important for the build-evaluate-fix loop where multiple sprints may be in flight.

---

## 16. Add a Branch Completion / PR Workflow Skill

After building, there's no standardized process for finishing: running final tests, creating a PR, cleaning up. The builder just... stops.

**Inspired by:** superpowers finishing-a-development-branch — a 4-step completion process.

**What to build:** A `finisher` skill invoked after the builder completes:
1. Run all tests and verify they pass
2. Present options to the user: merge locally, push and create PR, keep as-is, or discard
3. Require typed confirmation for destructive actions (discard)
4. Clean up worktrees, temporary files, build artifacts

**Integration:** The orchestrator should invoke this after the build loop ends and QA passes.

---

## 17. Improve Code Review with a "Receiving Review" Protocol

Our `code-reviewer` skill gives reviews. But there's no protocol for how the builder should process and act on review feedback. This leads to "yes sir" implementation of every suggestion without critical evaluation.

**Inspired by:** superpowers receiving-code-review — "Verify before implementing. Ask before assuming."

**What to add to `builder/SKILL.md`:**
1. Read the full review before acting on any item
2. Restate requirements to confirm understanding
3. Check if the codebase already handles the concern differently
4. Push back when: feedback contradicts working functionality, lacks context, or violates YAGNI
5. Implement one item at a time with individual testing
6. Never respond with performative agreement ("You're absolutely right!")
