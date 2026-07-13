
# Process Improvement Suggestions

Concrete improvements to the Spec-Driven AI pipeline, ordered by expected impact.

---

## 4. Version Sprint Contracts — ✅ DONE (2026-07-12)

Sprint contracts (`SPRINT_CONTRACT.md`) are overwritten each sprint. When the QA evaluator fails a build and the builder modifies testable behaviors, the original contract is lost.

**Change:** Name them `SPRINT_CONTRACT_001.md`, `SPRINT_CONTRACT_002.md`, etc. Or append a revision history section at the bottom. This gives you an audit trail of scope changes and helps identify scope creep.

**Done:** `builder.md` now writes numbered contracts + `## Revision history`; `qa-evaluator.md` reads the highest-numbered file.

---

## 8. Decouple Skills from `.claude/` Paths — 🟡 PARTIAL (2026-07-12)

Several skills hardcode paths like `.claude/PRODUCT_SPEC.md`, `.claude/tasks.yaml`, `.claude/SPRINT_CONTRACT.md`. The README mentions OpenCode compatibility, but the skills reference `.claude/` directly.

**Change:** Define a convention: use `$AGENT_DIR` or a config variable that defaults to `.claude/` but can be overridden. Or add a preamble to each skill: "Output directory: `.claude/` (or `.opencode/` if using OpenCode)."

**Done:** Path convention anchored in `orchestrator.md` (detect `.opencode/` else `.claude/`, pass resolved dir to dispatched agents).
**Remaining:** full sweep across all 7 skills + remaining agents that still hardcode `.claude/` (project-manager, summarizer-auditor, code-reviewer, and the skills under `skills/`).


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

---

## PASSE 2 — Import 4 high-value skills from mattpocock/skills (adapted 100% to this stack)

Context: 2026-07-12 we improved the agents (builder debug loop-first, orchestrator Bug lane + merge methodology, architect CONTEXT.md, versioned sprint contracts) so the agents already "speak" these skills' language. Next: bring in the skills themselves, adapted to dagRobin/RTK/OpenCode paths — NOT verbatim ports.

Skills to import (source: `mattpocock/skills/skills/engineering/<name>/SKILL.md`):

1. **diagnosing-bugs** — feedback-loop-first debugging (repro loop → 3-5 falsifiable hypotheses → one variable → regression test). Mirror the discipline now in `builder.md` Systematic Debugging mode, as a standalone invokable skill.
2. **wayfinder** — maps unclear/foggy work as a graph of investigation tickets resolved one at a time. **Map onto dagRobin directly**: tickets = tasks, blocking = `--deps`, "fog / Not yet specified" = `blocked` tasks. Gate BEFORE the architect when the destination is vague. Answers suggestions #1 (validate problem) + #11 (brainstorming).
3. **resolving-merge-conflicts** — assess → investigate intent via commits/long-description → reconcile without inventing behavior → validate → escalate only when blocked. Backs the orchestrator's new merge methodology; the natural home for a future `merge-captain` flow (worktree→merge).
4. **domain-modeling** — active glossary/ubiquitous-language discipline writing `CONTEXT.md`. Backs the architect's new CONTEXT.md section.

**Adaptation rules (100% to this stack):** rewrite to dagRobin (not a generic issue tracker), RTK-prefixed commands, `.claude/`↔`.opencode/` path convention. **Register each new skill in `opencode.json` and add `~/.codex/skills` is already a sync target** — then run `scripts/sync-skills.sh paths.txt`.

Optional lower-priority: `prototype` (throwaway spike, complements `estimator`), `grill-with-docs` (validate impl against real docs, anti-API-hallucination).

---

## PASSE 3 — New skill ideas (after Passe 2)

1. **`merge-captain`** — dedicated flow that closes the orchestrator's worktree→merge cycle using the resolving-merge-conflicts methodology. Today this is the most fragile point of parallel execution.
2. **`reality-check`** — a skill that invokes the available *Reality Checker* agent to force evidence-based certification at the end of the build-evaluate-fix loop (default "NEEDS WORK" until overwhelming proof). Currently the agent exists but no skill drives it.
3. **Incorporate `forrestchang/andrej-karpathy-skills`** (from `TODO_NEXT.txt`) — map which of its skills complement (not overlap) the current pipeline, then import the non-redundant ones under the same adaptation rules as Passe 2.
