---
name: peer-review
description: Multi-agent peer review panel. Coordinates specialist agents with distinct perspectives to analyze, rewrite, and consolidate code, documents, designs, or ideas. Trigger with "panel review", "run the panel", "multi-agent review", "/panel-review", "/panel", or when asked for deep critique, multiple viewpoints, or document refinement.
---

# Multi-Agent Peer Review & Document Refinement

Coordinates a simulated round-table of specialist agents to produce a final document demonstrably superior to the original through critical analysis, independent rewrites, blind peer review (NxN), and consolidated synthesis.

> **Trigger phrases:** "panel review", "run the panel", "multi-agent review", "/panel-review", "/panel", "deep review", "multiple takes", "panel critique", "improve this substantially"

---

## How to Invoke

### Natural Language (conversation)
Just say what you want:
- "panel review of myfile.md"
- "run the panel on this document with 3 agents"
- "multi-agent review of the proposal, focus on code"
- "deep review of X, make it adversarial"

### Slash Command (explicit)
Create `.claude/commands/peer-review.md`:
```markdown
# /peer-review
Use the peer-review skill on: $ARGUMENTS
```
Then: `/peer-review myfile.md`

### Variants — How to Specify
Specify in natural language or after slash command:

| Variant | Example |
|---------|---------|
| `--agents N` | "panel review with 8 agents" or `/peer-review file.md --agents 8` |
| `--focus type` | "focus on code", "review my docs" |
| `--style tone` | "make it adversarial", "cooperative review" |
| `--depth level` | "quick review", "deep analysis" |

---

## Phase 0 — Discovery & Calibration

Detect context and variants automatically:

1. **Document type?** (code, docs, design, prose, planning, RFC, proposal)
2. **Goal?** (improve, find bugs, prepare for publication, convince stakeholder)
3. **Constraints?** (audience, tone, format restrictions)

### Variants Detection
Parse from user's request or default to:

| Variant | Values | Default |
|---------|--------|---------|
| agents | 3+ | 6 |
| focus | code, docs, design, prose, planning | auto-detect |
| style | adversarial, cooperative | cooperative |
| depth | quick, standard, deep | standard |

Example resolutions:
- "quick review" → depth=quick, agents=3
- "4 agents" → agents=4
- "adversarial" → style=adversarial

---

## Phase 1 — Agent Creation (Randomized)

Create **6 agents** (default). **Randomize** name, specialty, priorities, and thinking style for each run. Use `RANDOM` or equivalent to pick from pools without replacement (no duplicates):

### Names
> Pick 6: Use `RANDOM` to shuffle, take first 6

```
# Full pool (175 names - occultists & alchemists)
Agrippa, Al-Razi, Albert, Alberto, Albertus, Aleister, Alexander, Alice, Altus, Andreas, Andrew, Anna, Annie, Antoine, Anton, Aquino, Arnaldo, Arthur, Ashmole, Austin, Avicena, Bacon, Bailey, Basílio, Bernard, Besant, Blaise, Boehme, Boyle, Böttger, Cagliostro, Canseliet, Carroll, Caterina, Charnock, Christian, Cleópatra, Cornelius, Crowley, Dee, Denis, Dickinson, Digby, Dubuis, Edward, Eirenaeus, Elias, Eliphas, Emanuel, Eugène, Evelyn, Evola, Flamel, Florence, Flowers, Fludd, Fortune, Francis, François, Frater, Fries, Fulcanelli, Geber, Genesis, George, Gerald, Gerhard, Gichtel, Gilles, Giordano, Giovanni, Glauber, Grant, Grigori, Gurdjieff, Guénon, Hakim, Hartmann, Heindel, Heinrich, Helena, Helmont, Hermes, Hine, Ida, Isaac, Isabella, Israel, Jacob, Jacques, Jan, Jean, Johann, Johannes, John, Josephine, Judge, Julius, Junius, Kelley, Kellner, Kenelm, Kenneth, Khunrath, Kunckel, LaVey, Leadbeater, Leona, Libavius, Limojon, Lon, Maier, Manfred, Manly, Margaret, Maria, Marjorie, Marsilio, Martin, Mary, Mathers, Melchior, Michael, Moina, Nema, Newton, Nicolas, Norton, Olcott, Ortolanus, Oswald, Pamela, Papus, Paracelso, Paschal, Pernell, Peter, Petrus, Phil, Philalethes, Piotr, Raimundo, Regardie, René, Reuss, Richard, Ripley, Robert, Roger, Rosaleen, Rudolf, Saint-Germain, Samuel, Schwaller, Sendivogius, Sherwin, Sinnett, Soror, Spare, Stanislas, Starkey, Steiner, Stephen, Thomas, Trithemius, Tycho, Valentin, Valentinus, Vaughan, Waite, Westcott, William, Zósimo
```

### Specialties
> Pick 6: Use `RANDOM`

```
# Technical (25)
Backend Architecture, Frontend Architecture, Database Design, DevOps & Infrastructure, Security & Cryptography, Performance Optimization, API Design & REST, Microservices, Real-time Systems, Data Engineering, Machine Learning Ops, Cloud Infrastructure, Testing Strategy, CI/CD Pipelines, Observability & Logging, Error Handling & Resilience, State Management, Component Design, Accessibility (a11y), Internationalization, Mobile Development, Embedded Systems, Networking, Graphics & UI, Audio/Video Streaming, Blockchain

# Domain (25)
Product Strategy, UX Research, Technical Writing, Technical Leadership, Engineering Management, Architecture & Scalability, Incident Response, Code Review, Refactoring, Technical Debt, Standards & Governance, Developer Experience, Platform Engineering, Developer Advocacy, Open Source, Startups & MVP, Enterprise, Compliance & Privacy, Performance Auditing, Debugging & Troubleshooting, Test Automation, Integration, Migration, Bootstrapping, Prototyping, Incident Management
```

### Priorities (Quotations)
> Pick 6: Use `RANDOM`

```
"Works > theory", "Clean abstractions", "Brevity with completeness", "Defensive design", "Coherence over fragments", "Challenge assumptions", "Future-proofing", "User-first", "Minimal friction", "Explicit over implicit", "Convergence", "Find missing context", "Speed of delivery", "Maintainability", "Testability", "Performance > readability", "Readability > cleverness", "Convention over configuration", "Progressive enhancement", "Fail fast, fail loud", "Boring technology", "Elegance over safety", "Safety over elegance", "Deep over wide", "Wide over deep", "Self-documenting code", "Comments everywhere", "No magic", "Convention locks", "Flexibility > structure"
```

### Thinking Styles
> Pick 6: Use `RANDOM`

```
# Styles (25)
Practical/grounded, Strategic/structural, Analytical/user-centric, Adversarial/thorough, Integrative/holistic, Interrogative/Socratic, Creative/divergent, Conservative/cautious, Fast/decisive, Methodical/rigorous, Minimalist/essentialist, Maximalist/comprehensive, Optimistic/possibility-focused, Pessimist/risk-focused, Empathetic/collaborative, Independent/maverick, Diplomatic/balanced, Ruthless/pragmatic, Guarded/pessimistic, Experimental/iterative, Formal/rigid, Casual/pragmatic, Detail-oriented, Big-picture, Bottom-up, Top-down, Lateral/thinking, Vertical/depth-first, Questioning/convention-challenger, Rule-abiding/convention-follower
```

**Generation rule:** For each run, use `RANDOM` to shuffle each pool and pick top 6 without replacement. Re-roll if you get duplicates.

---

## Phase 2 — Independent Analysis

Each agent produces a structured analysis of the original:

- **Strengths** — what deserves preservation
- **Weaknesses** — what's poorly handled
- **Gaps** — what's missing entirely
- **Possible improvements** — concrete proposals
- **Risks** — traps, debts, latent failures

---

## Phase 3 — Independent Rewrite

Each agent produces its own improved version. Complete restructuring allowed. Single constraint: each version must be **demonstrably superior** to the original.

---

## Phase 4 — Peer Review (NxN Matrix)

Each agent reviews **only others' versions** (self-review forbidden).

### Scoring Criteria (0-10)

1. **Clarity** — ease of understanding
2. **Quality** — technical/argumentative soundness
3. **Consistency** — holds up under scrutiny
4. **Structure** — flow and hierarchy
5. **Originality** — beyond the obvious

### Written Feedback

2-4 lines of specific critique per version. No generic praise or empty criticism. Genuine disagreement is a **quality signal**.

---

## Phase 5 — Evaluation Analysis

Identify patterns:

- **Highest weighted averages** — versions that scored best
- **Convergent ideas** — appeared in multiple versions
- **Recurring problems** — appeared in multiple critiques
- **Explicit tensions** — conflicts needing resolution

---

## Phase 6 — Consolidated Final Document

Produce a single final version that:

- Incorporates best ideas from individual versions
- Explicitly resolves each tension (declare winner + why)
- Fills legitimate gaps with justified proposals
- Surpasses **every individual version**
- Maintains voice and structure coherence

If not clearly superior to all, repeat Phase 6 focusing on weakest points.

---

## Output Format

1. **Agents** — full profiles (randomized)
2. **Analysis** — one section per agent
3. **Versions** — complete documents, clearly delimited
4. **NxN Matrix** — score table
5. **Feedback** — written critiques
6. **Analysis** — synthesis of patterns
7. **Final Document** — consolidated version