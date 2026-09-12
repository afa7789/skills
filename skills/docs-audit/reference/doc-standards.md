# Documentation standards — fallback reference

Use this only when the repository has no `docs/DOCUMENTATION.md`. When that file exists, it wins on every point.

## Diátaxis — four kinds of documentation

Separate documents by the reader's need. Never mix two modes in one document.

| Mode | Reader need | Written as |
|---|---|---|
| **Tutorial** | "Teach me" — learning by doing | A guaranteed-to-work lesson, concrete, no choices, no explanation detours |
| **How-to guide** | "Help me do X" — a real task | Ordered steps for a goal the reader already has; assumes competence |
| **Reference** | "Tell me the facts" | Dry, complete, consistent description of the machinery: APIs, flags, config, schemas |
| **Explanation** | "Help me understand" | Background, architecture, trade-offs, why decisions were made |

Common failures: reference buried inside a tutorial; explanation interrupting a how-to; a "guide" that is really an unsorted reference dump.

## Google developer documentation style — the load-bearing rules

- **Answer first.** Put the conclusion, the command, or the result in the first sentence. Context after.
- **Active voice.** "The service validates the token", not "the token is validated".
- **Present tense.** "Returns 404", not "will return 404".
- **One main idea per paragraph.** Topic in the first sentence.
- **Second person.** "You configure…", not "the user configures…".
- **Introduce technical terms** on first use, then use exactly that term everywhere. No synonyms.
- **Short sentences.** Split anything that carries two instructions.
- **Describe the action, not the UI mechanics.** "Set the retry limit", not "click the box and type".
- **Lists** for anything enumerable; **tables** for anything with parallel attributes; **numbered steps** for procedures.
- **Code, paths, flags, and identifiers** in code formatting, always.

## Headings

A heading must let the reader predict what follows and decide whether to read it.

- Task headings are gerund or imperative phrases: "Deploying the worker", "Configure TLS".
- Reference headings are the name of the thing.
- No clever, empty, or one-word-abstract headings ("Overview" is acceptable only for an actual overview).
- Sentence case. Unique within the document. Never skip a level.

## Repository convention — function before identifier

Describe what a component does, then name it.

- Good: `financial service (apps/orchestrator)`
- Bad: `apps/orchestrator — handles money stuff`

Apply the same order in headings, tables, and diagrams.

## Placement rules of thumb

- A fact has exactly **one** home document. Everything else links to it.
- Operational and deployment facts belong in operational docs, not in the architecture explanation.
- Package-level READMEs describe that package's purpose and its public surface — not the whole system.
- The top-level README orients a newcomer and routes them; it is not a reference.
