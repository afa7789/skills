---
name: docs-audit
description: Audit every documentation file against the current code and the repository's documentation standard.
disable-model-invocation: true
---

# Docs Audit — documentation vs. the actual codebase

Two sources of truth:

1. **The codebase** — the only authority on implemented behavior.
2. **`docs/DOCUMENTATION.md`** — the authority on where docs live and how they are written.

Documentation never proves itself. Every claim gets checked against code.

Related: [`ste-docs`](../ste-docs/SKILL.md) rewrites prose style. This skill fixes *truth* and *placement*. Run this one first.

---

## ⚠️ Hard requirement — REAL subagents

Per-file verification runs as real `Agent` tool calls, dispatched in parallel — one batch per agent. The main thread only discovers, batches, dispatches, reconciles, verifies, reports. If the `Agent` tool is unavailable, STOP and tell the user.

---

## Phase 0 — Standard and scope

1. Read `docs/DOCUMENTATION.md` **in full**. Pay attention to:
   - where documentation belongs;
   - writing for quick reading;
   - project, deployment, operational, and reference documentation.
   Its rules decide the correct document and location for each subject **before** you create, move, or restructure anything.
2. If `docs/DOCUMENTATION.md` does not exist: tell the user, and fall back to [`reference/doc-standards.md`](reference/doc-standards.md) (Diátaxis + Google developer style summary). Offer to generate a `docs/DOCUMENTATION.md` at the end.
3. Confirm a clean working tree (`rtk git status`). Create a branch:
   ```bash
   rtk git checkout -b docs/audit
   ```
4. Default scope — state it, then proceed: all `*.md`/`*.mdx`/`*.rst` under the repo, including `docs/**`, package-level READMEs, operational/deployment docs, architecture docs. Exclude `node_modules`, `vendor`, `target`, `dist`, `build`, generated API dumps, third-party text.

---

## Phase 1 — Inventory

```bash
rtk find "*.md" ; rtk find "*.mdx" ; rtk find "*.rst"
```

For each file record: path, apparent purpose, Diátaxis category (explanation / tutorial / how-to / reference), and the subsystems it describes.

Write the manifest to `.claude/DOCS_AUDIT_MANIFEST.md`:

| # | File | Purpose | Category | Subsystems described | Batch |
|---|------|---------|----------|----------------------|-------|

---

## Phase 2 — Batching

- Batch **by subsystem, not by directory** — the agent that verifies the deploy doc should also verify the deploy section of the README.
- ~4–8 files per batch. A large architecture doc gets its own batch.
- One file in exactly one batch — agents must never edit the same file.
- Pass every agent the same glossary of component names (extract from the top-level README + `docs/DOCUMENTATION.md`) so terminology stays consistent.

---

## Phase 3 — Dispatch verifier subagents

Spawn one subagent per batch, **in a single message**, agent type `general-purpose`.

Contract for each agent:

```
You audit documentation against the CURRENT CODEBASE.

SOURCES OF TRUTH
- The code is the only authority on implemented behavior.
- <repo>/docs/DOCUMENTATION.md is the authority on doc organization and
  writing style. Read it in full before editing. (If missing, use
  <repo>/skills/docs-audit/reference/doc-standards.md.)

FOR EACH FILE IN YOUR BATCH
1. Read the whole document.
2. Determine its purpose and Diátaxis category.
3. List the code, config, APIs, components, deployment topology, flows,
   responsibilities and behavior it describes.
4. OPEN THE CORRESPONDING IMPLEMENTATION. Verify every technical claim
   against it — names, paths, flags, env vars, endpoints, ports, commands,
   defaults, ordering, guarantees.
5. Fix what is outdated, inaccurate, incomplete, ambiguous or misleading.
6. Add missing information needed to describe the current implementation.
7. Delete documentation for behavior, components, flows, config or
   architecture that no longer exists.
8. Make terminology and component names consistent and declarative.
9. Describe what a component DOES before naming its identifier or path —
   repo convention: "financial service (apps/orchestrator)".
10. Make architectural boundaries, responsibilities, deployment boundaries
    and component interactions explicit.

STRICT ACCURACY RULES
- Never infer behavior from other documentation. Only from code, config,
  tests, or repository history.
- Never present planned, proposed, deprecated or partially implemented
  behavior as currently implemented. Label it explicitly if you keep it.
- Distinguish current behavior from historical context when history is
  genuinely useful.
- Invent nothing: no architecture, responsibilities, guarantees, APIs,
  deployment relationships or flows you cannot point to in the code.
- On conflict, the documentation changes to match the code.
- If intent is genuinely ambiguous and the code, config, tests and git
  history cannot resolve it: DO NOT GUESS. Flag it for the user.

PLACEMENT
- Preserve existing style and structure when already compliant. Restructure
  only when it materially improves correctness, discoverability or clarity.
- Before creating a new file, check DOCUMENTATION.md that the subject does
  not already belong in an existing document.

FILES: <batch list>
GLOSSARY: <component names + canonical descriptions>

OUTPUT (per file): claims checked, discrepancies found and how each was
resolved (with the code path that proves it), content removed and why,
content added, structural changes, and every unresolved ambiguity.
```

---

## Phase 4 — Reconcile in the main thread

Agents worked in parallel and cannot see each other. The main thread fixes the seams:

1. **Cross-file duplication** — same fact in two docs? Keep it in the responsible document per `DOCUMENTATION.md`, replace the others with a link.
2. **Contradictions** between batches — re-check against the code yourself and pick the correct version.
3. **Moves and creations** — validate each against `DOCUMENTATION.md`. Undo any new file whose subject belonged in an existing doc.
4. **Terminology drift** — unify component names repo-wide.
5. **Coverage gap** — any subsystem with no owning document? Note it as missing documentation; add it only where `DOCUMENTATION.md` says it belongs.

---

## Phase 5 — Verify

1. `rtk git diff --stat`, then read the largest diffs. No code files changed.
2. Links and anchors intact after any move or rename.
3. Every command, path and identifier appearing in the docs actually exists:
   ```bash
   rtk npx markdownlint "**/*.md" 2>/dev/null || true
   ```
   Spot-check code paths and CLI flags by running or grepping them.
4. Re-read a sample of files against the `DOCUMENTATION.md` rules.
5. Collect every flagged ambiguity — resolve with the user, never silently.

The audit is repo-wide: it is done only when every file in the manifest is marked verified.

---

## Phase 6 — Report

Write `.claude/DOCS_AUDIT_REPORT.md` and show the user a summary:

```markdown
# Documentation Audit Report

**Branch:** docs/audit   **Date:** <date>
**Standard:** docs/DOCUMENTATION.md (Diátaxis, Google developer style)

## Files reviewed
<count + list>

## Files changed
## Files created / moved / removed  (with the DOCUMENTATION.md rule that justifies each)

## Major discrepancies found and how they were resolved
| Doc | Claimed | Actual (code path) | Resolution |

## Structural / documentation-standard issues corrected
## Missing documentation added
## Remaining ambiguities and open questions
```

Final state must satisfy both:
1. Documentation accurately represents the current implementation.
2. Documentation is organized and written per `docs/DOCUMENTATION.md`.

Commit only when the user asks, with their exact message.

---

## Anti-patterns

- "Looks plausible" — if you did not open the implementation, the claim is unverified.
- Documenting the plan instead of the build.
- Stopping at `ARCHITECTURE.md`.
