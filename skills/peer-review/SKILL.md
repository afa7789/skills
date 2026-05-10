---
name: peer-review
description: Multi-agent peer review panel. Spawns real subagents in parallel via the Agent tool — each with a distinct randomized persona — to analyze, rewrite, peer-review (NxN), and consolidate code, documents, designs, or ideas. Trigger with "panel review", "run the panel", "multi-agent review", "/panel-review", "/panel", or when asked for deep critique, multiple viewpoints, or document refinement.
---

# Multi-Agent Peer Review & Document Refinement

Coordinates a real round-table of independent subagents (spawned via the `Agent` tool) to produce a final document demonstrably superior to the original through critical analysis, independent rewrites, blind peer review (NxN), and consolidated synthesis.

> **Trigger phrases:** "panel review", "run the panel", "multi-agent review", "/panel-review", "/panel", "deep review", "multiple takes", "panel critique", "improve this substantially"

---

## ⚠️ Hard Requirement — REAL Agent Spawning, Not Role-Play

This skill is **only valid** when each persona is dispatched as a real `Agent` tool call (subagent). Do NOT role-play 6 voices in a single response. The whole point of the panel is **genuine independence**: isolated context, non-deterministic outputs, real disagreement.

**Forbidden:** generating all 6 analyses / rewrites / reviews inline as the main thread.
**Required:** issue real `Agent(...)` invocations — in parallel, in a single message — and consolidate their returned outputs.

If for any reason you cannot spawn agents (e.g. tool unavailable), STOP and tell the user, do not silently fall back to simulation.

---

## How to Invoke

### Natural Language
- "panel review of myfile.md"
- "run the panel on this document with 4 agents"
- "multi-agent review of the proposal, focus on code"
- "deep review of X, make it adversarial"

### Slash Command
`.claude/commands/peer-review.md`:
```markdown
# /peer-review
Use the peer-review skill on: $ARGUMENTS
```

### Variants

| Variant | Example |
|---------|---------|
| `--agents N` | "panel review with 8 agents" |
| `--focus type` | "focus on code", "review my docs" |
| `--style tone` | "make it adversarial", "cooperative review" |
| `--depth level` | "quick review", "deep analysis" |

Defaults: `agents=6`, `focus=auto-detect`, `style=cooperative`, `depth=standard`.
Quick mode: `agents=3, depth=quick`. Deep mode: `agents=6, depth=deep`.

---

## Phase 0 — Discovery & Calibration (main thread)

1. Read the target artifact (file, snippet, paste).
2. Detect document type (code / docs / design / prose / planning / RFC).
3. Resolve variants from the user's phrasing.
4. Build a shared **brief packet** that every spawned agent will receive verbatim:
   - Original artifact (full content, not a summary)
   - Goal of the review
   - Focus / style / depth
   - Output contract (see Phase 2 below)

---

## Phase 1 — Persona Generation (main thread, randomized)

Generate `N` personas (default 6). For each, randomly draw — **without replacement across the panel** — one item from each pool. Re-roll on duplicates.

### Names (occultists & alchemists pool)
```
Agrippa, Al-Razi, Albert, Alberto, Albertus, Aleister, Alexander, Alice, Altus, Andreas, Andrew, Anna, Annie, Antoine, Anton, Aquino, Arnaldo, Arthur, Ashmole, Austin, Avicena, Bacon, Bailey, Basílio, Bernard, Besant, Blaise, Boehme, Boyle, Böttger, Cagliostro, Canseliet, Carroll, Caterina, Charnock, Christian, Cleópatra, Cornelius, Crowley, Dee, Denis, Dickinson, Digby, Dubuis, Edward, Eirenaeus, Elias, Eliphas, Emanuel, Eugène, Evelyn, Evola, Flamel, Florence, Flowers, Fludd, Fortune, Francis, François, Frater, Fries, Fulcanelli, Geber, Genesis, George, Gerald, Gerhard, Gichtel, Gilles, Giordano, Giovanni, Glauber, Grant, Grigori, Gurdjieff, Guénon, Hakim, Hartmann, Heindel, Heinrich, Helena, Helmont, Hermes, Hine, Ida, Isaac, Isabella, Israel, Jacob, Jacques, Jan, Jean, Johann, Johannes, John, Josephine, Judge, Julius, Junius, Kelley, Kellner, Kenelm, Kenneth, Khunrath, Kunckel, LaVey, Leadbeater, Leona, Libavius, Limojon, Lon, Maier, Manfred, Manly, Margaret, Maria, Marjorie, Marsilio, Martin, Mary, Mathers, Melchior, Michael, Moina, Nema, Newton, Nicolas, Norton, Olcott, Ortolanus, Oswald, Pamela, Papus, Paracelso, Paschal, Pernell, Peter, Petrus, Phil, Philalethes, Piotr, Raimundo, Regardie, René, Reuss, Richard, Ripley, Robert, Roger, Rosaleen, Rudolf, Saint-Germain, Samuel, Schwaller, Sendivogius, Sherwin, Sinnett, Soror, Spare, Stanislas, Starkey, Steiner, Stephen, Thomas, Trithemius, Tycho, Valentin, Valentinus, Vaughan, Waite, Westcott, William, Zósimo
```

### Specialties
```
# Technical
Backend Architecture, Frontend Architecture, Database Design, DevOps & Infrastructure, Security & Cryptography, Performance Optimization, API Design & REST, Microservices, Real-time Systems, Data Engineering, Machine Learning Ops, Cloud Infrastructure, Testing Strategy, CI/CD Pipelines, Observability & Logging, Error Handling & Resilience, State Management, Component Design, Accessibility (a11y), Internationalization, Mobile Development, Embedded Systems, Networking, Graphics & UI, Audio/Video Streaming, Blockchain
# Domain
Product Strategy, UX Research, Technical Writing, Technical Leadership, Engineering Management, Architecture & Scalability, Incident Response, Code Review, Refactoring, Technical Debt, Standards & Governance, Developer Experience, Platform Engineering, Developer Advocacy, Open Source, Startups & MVP, Enterprise, Compliance & Privacy, Performance Auditing, Debugging & Troubleshooting, Test Automation, Integration, Migration, Bootstrapping, Prototyping, Incident Management
```

### Priorities (mottos)
```
"Works > theory", "Clean abstractions", "Brevity with completeness", "Defensive design", "Coherence over fragments", "Challenge assumptions", "Future-proofing", "User-first", "Minimal friction", "Explicit over implicit", "Convergence", "Find missing context", "Speed of delivery", "Maintainability", "Testability", "Performance > readability", "Readability > cleverness", "Convention over configuration", "Progressive enhancement", "Fail fast, fail loud", "Boring technology", "Elegance over safety", "Safety over elegance", "Deep over wide", "Wide over deep", "Self-documenting code", "Comments everywhere", "No magic", "Convention locks", "Flexibility > structure"
```

### Thinking Styles
```
Practical/grounded, Strategic/structural, Analytical/user-centric, Adversarial/thorough, Integrative/holistic, Interrogative/Socratic, Creative/divergent, Conservative/cautious, Fast/decisive, Methodical/rigorous, Minimalist/essentialist, Maximalist/comprehensive, Optimistic/possibility-focused, Pessimist/risk-focused, Empathetic/collaborative, Independent/maverick, Diplomatic/balanced, Ruthless/pragmatic, Guarded/pessimistic, Experimental/iterative, Formal/rigid, Casual/pragmatic, Detail-oriented, Big-picture, Bottom-up, Top-down, Lateral/thinking, Vertical/depth-first, Questioning/convention-challenger, Rule-abiding/convention-follower
```

Pick the `subagent_type` from the catalog when a specialty has a strong match (e.g. `Security Engineer`, `Code Reviewer`, `UX Architect`, `Backend Architect`, `Frontend Developer`, `Performance Benchmarker`, `Accessibility Auditor`). Otherwise default to `general-purpose`. Variation in subagent_type is encouraged — it amplifies non-determinism.

---

## Phase 2 — Parallel Analysis + Rewrite (REAL Agent calls)

Spawn **all N agents in a single message**, each as a distinct `Agent` tool invocation (parallel execution). Each agent receives the brief packet plus its persona block, and is asked to produce **both** the analysis and the rewrite in one shot — this halves spawn count and keeps the agent's voice coherent across analysis→rewrite.

### Per-agent prompt template (verbatim shape)

```
You are {NAME}, specialty: {SPECIALTY}. Motto: "{PRIORITY}". Thinking style: {STYLE}.

You are participating in a peer-review panel with {N-1} other independent reviewers
who you cannot see. Stay strictly in character — your specialty and motto must
visibly drive your judgments. Disagree with conventional wisdom when your
perspective demands it; the panel rewards genuine divergence.

ORIGINAL ARTIFACT:
<<<
{FULL_ORIGINAL_CONTENT}
>>>

GOAL: {GOAL}
FOCUS: {FOCUS}   STYLE: {STYLE_VARIANT}   DEPTH: {DEPTH}

Produce, in this exact order, two sections:

## ANALYSIS
- Strengths — what deserves preservation
- Weaknesses — what is poorly handled
- Gaps — what is missing entirely
- Improvements — concrete proposals
- Risks — traps, debt, latent failures

## REWRITE
A complete improved version of the artifact. Restructuring is allowed and
encouraged. The single hard constraint: your rewrite must be demonstrably
superior to the original from your specialty's vantage point.

Return ONLY those two sections. No preamble, no meta-commentary about being
an agent.
```

### Spawn rules
- **One message, N parallel `Agent` calls.** Do not serialize.
- Each `Agent` call gets a unique `description` like `"Panel: {NAME} analysis+rewrite"`.
- Capture each agent's full returned text keyed by persona.
- If an agent fails or returns malformed output, re-spawn just that one with the same prompt; do not patch the gap inline.

---

## Phase 3 — Parallel Blind Peer Review (REAL Agent calls)

Spawn **N more agents in a single parallel message**. Each agent reviews the **other N-1 rewrites** (self-review forbidden) and returns a structured score table + written critiques.

### Per-reviewer prompt template

```
You are {NAME}, specialty: {SPECIALTY}. Motto: "{PRIORITY}". Style: {STYLE}.

Below are {N-1} anonymized rewrites of the same original artifact, produced by
your peers. You did NOT write any of these — review them honestly.

ORIGINAL ARTIFACT (for reference):
<<<
{FULL_ORIGINAL_CONTENT}
>>>

PEER REWRITES (anonymized as V1..V{N-1}):
<<<
V1:
{rewrite_from_other_agent_1}

V2:
{rewrite_from_other_agent_2}

...
>>>

For EACH version, score 0–10 on:
- Clarity (ease of understanding)
- Quality (technical/argumentative soundness)
- Consistency (holds up under scrutiny)
- Structure (flow and hierarchy)
- Originality (beyond the obvious)

Then write 2–4 lines of specific critique per version. No generic praise. No
empty criticism. Genuine disagreement is rewarded.

Return:

## SCORES
| Version | Clarity | Quality | Consistency | Structure | Originality |
|---------|---------|---------|-------------|-----------|-------------|
| V1      | ...     | ...     | ...         | ...       | ...         |
...

## CRITIQUES
### V1
{2–4 lines}
### V2
{2–4 lines}
...
```

### Anonymization rule
The main thread MUST shuffle which rewrite ID maps to which persona for each reviewer (or use a single global anonymization), so reviewers cannot infer authorship from order. Keep the mapping privately on the main thread to de-anonymize later.

---

## Phase 4 — Synthesis (main thread)

After all reviewer agents return:

1. De-anonymize and aggregate scores → mean + variance per rewrite.
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

If the consolidated draft is not clearly superior to all rewrites on at least 4 of the 5 axes, iterate once more focusing on the weakest axis. Optionally spawn one more `Agent` (e.g. `Code Reviewer` or `scribe`) to do a final pass.

---

## Output Format (to the user)

1. **Panel** — list of personas (name, specialty, motto, style, subagent_type used)
2. **Analyses** — one section per agent, verbatim from agent output
3. **Rewrites** — full rewrites, clearly delimited
4. **NxN Matrix** — aggregated score table
5. **Critiques** — written critiques per rewrite
6. **Synthesis** — convergence, tensions, resolutions
7. **Final Document** — consolidated version

---

## Anti-Patterns (do not do)

- ❌ Generating all 6 analyses inline without spawning agents.
- ❌ Spawning agents serially instead of in one parallel message.
- ❌ Letting an agent see its own rewrite during peer review.
- ❌ Asking each agent to "imagine other reviewers" — defeats the panel.
- ❌ Truncating the original artifact in the per-agent prompt — every agent needs the full text.
- ❌ Skipping the tension-resolution step in Phase 5.
