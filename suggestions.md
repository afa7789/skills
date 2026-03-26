
# Process Improvement Suggestions

Concrete improvements to the Spec-Driven AI pipeline, ordered by expected impact.

---

## 4. Version Sprint Contracts

Sprint contracts (`SPRINT_CONTRACT.md`) are overwritten each sprint. When the QA evaluator fails a build and the builder modifies testable behaviors, the original contract is lost.

**Change:** Name them `SPRINT_CONTRACT_001.md`, `SPRINT_CONTRACT_002.md`, etc. Or append a revision history section at the bottom. This gives you an audit trail of scope changes and helps identify scope creep.

**Files to modify:**
- `builder/SKILL.md` — change contract naming convention
- `qa-evaluator/SKILL.md` — read the latest numbered contract

---

## 8. Decouple Skills from `.claude/` Paths

Several skills hardcode paths like `.claude/PRODUCT_SPEC.md`, `.claude/tasks.yaml`, `.claude/SPRINT_CONTRACT.md`. The README mentions OpenCode compatibility, but the skills reference `.claude/` directly.

**Change:** Define a convention: use `$AGENT_DIR` or a config variable that defaults to `.claude/` but can be overridden. Or add a preamble to each skill: "Output directory: `.claude/` (or `.opencode/` if using OpenCode)."

**Files to modify:** All skills that reference `.claude/` paths (planner, builder, qa-evaluator, orchestrator, task-splitter, architect, summarizer-auditor).


---

## 1. Add "Step 0: Validate the Problem"

The pipeline starts with "brain-dump all ideas." There is no explicit step to validate that the problem is worth solving.

**Add before Step 1:** A lightweight validation gate. Who is the user? What problem do they have? Can you find 3 people who would use this? This prevents building well-specified solutions to problems nobody has.

**Implementation:** Add a validation template to the planner skill that asks 3 questions before proceeding: (1) Who specifically will use this? (2) What are they doing today instead? (3) Why would they switch?

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
