---
name: peer-review
description: Multi-agent peer review panel: parallel subagents analyse, rewrite, cross-review and consolidate.
disable-model-invocation: true
---

# Multi-Agent Peer Review & Document Refinement

Coordinates a real round-table of independent subagents (spawned via the `Agent` tool) to produce a final document demonstrably superior to the original through critical analysis, independent rewrites, blind peer review (N x (N-1), self-review forbidden), and consolidated synthesis.

Boundary: this skill runs persona panels over a document, prompt, or design (anything without a base branch). Reviewing a code diff or PR is `pr-review-pipeline`'s domain — route those there instead.

---

## ⚠️ Hard Requirement — REAL Agent Spawning, Not Role-Play

Dispatch each persona as a real `Agent` tool call (subagent), one per isolated context. That isolation is the whole point of the panel: **genuine independence** — non-deterministic outputs, real disagreement — which role-playing every voice in a single response cannot produce.

If you cannot spawn agents (e.g. tool unavailable), stop and tell the user instead of simulating the panel yourself.

---

## How to Invoke

### Natural Language
- "panel review of myfile.md"
- "run the panel on this document with 4 agents"
- "multi-agent review of the proposal, focus on code"
- "deep review of X with 9 agents"

### Variants

| Variant | Example |
|---------|---------|
| `--agents N` | "panel review with 8 agents", "quick review" (3), "deep analysis" (9) |
| `--focus type` | "focus on code", "review my docs" |

Defaults: `agents=6`, `focus=auto-detect`.

---

## Phase 0 — Discovery & Calibration (main thread)

1. Read the target artifact (file, snippet, paste).
2. Detect document type (code / docs / design / prose / planning / RFC).
3. Resolve variants from the user's phrasing.
4. Build a shared **brief packet** that every spawned agent will receive verbatim:
   - Original artifact (full content, not a summary)
   - Goal of the review
   - Focus
   - Output contract (see Phase 2 below)

---

## Phase 1 — Persona Generation (main thread, randomized)

Generate `N` personas (default 6). Assign each a short distinct label (`P1`..`PN`, or any distinct names you invent) — Phase 3 anonymizes rewrites by ID, so no reviewer ever sees the label. Read [`reference/panel-prompts.md`](reference/panel-prompts.md) in full: for specialty, motto and thinking style, randomly draw — **without replacement across the panel** — one item from each pool it lists. Re-roll on duplicates.

Dispatch every persona as `subagent_type: general-purpose` — the persona lives in the prompt, not in the type. Reach for `code-reviewer`, `architect` or `qa-evaluator` only where a specialty maps exactly onto one of those agents. Non-determinism comes from the specialty, motto and thinking-style draw, not from the agent type.

---

## Phase 2 — Parallel Analysis + Rewrite (REAL Agent calls)

Spawn **all N agents in a single message**, each as a distinct `Agent` tool invocation (parallel execution). Each agent receives the brief packet plus its persona block, and is asked to produce **both** the analysis and the rewrite in one shot — this halves spawn count and keeps the agent's voice coherent across analysis→rewrite.

### Per-agent prompt template

Read [`reference/panel-prompts.md`](reference/panel-prompts.md) in full and send its Phase 2 template verbatim, with `{NAME}`, `{SPECIALTY}`, `{PRIORITY}`, `{STYLE}`, `{FULL_ORIGINAL_CONTENT}`, `{GOAL}` and `{FOCUS}` interpolated per persona.

### Spawn rules
- **One message, N parallel `Agent` calls.**
- Each `Agent` call gets a unique `description` like `"Panel: {NAME} analysis+rewrite"`.
- Capture each agent's full returned text keyed by persona.
- If an agent fails or returns malformed output, re-spawn just that one with the same prompt; do not patch the gap inline.

---

## Phase 3 — Parallel Blind Peer Review (REAL Agent calls)

Spawn **N more agents in a single parallel message**. Each agent reviews only the **other N-1 rewrites it is handed** (self-review forbidden) and returns a structured score table + written critiques — it critiques what's on the page, not peers it cannot see.

### Per-reviewer prompt template

Read [`reference/panel-prompts.md`](reference/panel-prompts.md) in full and send its Phase 3 template verbatim, with `{NAME}`, `{SPECIALTY}`, `{PRIORITY}`, `{STYLE}`, `{FULL_ORIGINAL_CONTENT}` and the anonymized `V1..V{N-1}` rewrites interpolated per reviewer.

### Anonymization rule
The main thread MUST shuffle which rewrite ID maps to which persona for each reviewer (or use a single global anonymization), so reviewers cannot infer authorship from order. Keep the mapping privately on the main thread to de-anonymize later.

---

## Phase 4 — Synthesis (main thread)

After all reviewer agents return:

1. De-anonymize and aggregate scores with a short script (mean + variance per rewrite), not by hand.
2. Identify:
   - **Top-scoring rewrites** (highest weighted average)
   - **Convergent ideas** (appeared in 2+ rewrites or 2+ critiques)
   - **Recurring critiques** (appeared across multiple reviewers)
   - **Explicit tensions** (rewrites or critiques that directly conflict — these MUST be resolved by name in the final doc)

---

## Phase 5 — Consolidated Final Document (main thread, or one final Agent)

Produce a single final version that:
- Incorporates the strongest ideas from individual rewrites
- Explicitly resolves each tension (declare winner + the reason)
- Fills legitimate gaps with justified additions
- Surpasses **every individual rewrite** on the panel's own scoring axes
- Maintains a coherent voice and structure

If the consolidated draft is not clearly superior to all rewrites on at least 4 of the 5 axes, iterate once more focusing on the weakest axis. Optionally spawn one more `Agent` (`code-reviewer`) to do a final pass.

---

## Output Format (to the user)

1. **Panel** — list of personas (name, specialty, motto, style, subagent_type used)
2. **Analyses** — one section per agent, verbatim from agent output
3. **Rewrites** — full rewrites, clearly delimited
4. **N x (N-1) Matrix** — aggregated score table
5. **Critiques** — written critiques per rewrite
6. **Synthesis** — convergence, tensions, resolutions
7. **Final Document** — consolidated version

