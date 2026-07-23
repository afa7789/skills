---
name: ste-docs
description: Rewrite all repository documentation in ASD-STE100 Simplified Technical English. Discovers every doc and doc-comment scattered across the repo, batches them, and dispatches parallel subagents to correct, update, and reformat each file against the 53 STE writing rules and the ~900-word approved vocabulary. Trigger with "ste docs", "simplify the docs", "apply Simplified Technical English", "/ste-docs".
---

# STE Docs — Simplified Technical English for the whole repository

Find every document and code-documentation file in the repository, then use parallel subagents to rewrite them in **ASD-STE100 Simplified Technical English (Issue 9, January 2025)**. The result reads the same for every reader: one meaning per word, one verb per action, no floreio.

> **Trigger phrases:** "ste docs", "simplify the docs", "apply Simplified Technical English", "ASD-STE100", "/ste-docs", "make the docs STE"

The full rule set and the approved-word guidance live in [`reference/asd-ste100-rules.md`](reference/asd-ste100-rules.md). Read that file before you rewrite anything, and pass it to every subagent.

---

## ⚠️ Hard requirement — REAL subagents, not role-play

Rewrites run as real `Agent` tool calls (subagents), dispatched in parallel — one batch of files per agent. Do NOT rewrite every file inline in the main thread. The main thread only discovers, batches, dispatches, and verifies.

If the `Agent` tool is unavailable, STOP and tell the user. Do not silently fall back to rewriting everything yourself.

---

## Phase 0 — Scope and safety

1. Confirm the working tree is clean (`rtk git status`). If it is dirty, tell the user and ask whether to continue — the rewrite touches many files and a clean baseline makes review easy.
2. Create a branch so the change is reviewable and reversible:
   ```bash
   rtk git checkout -b docs/ste-rewrite
   ```
3. Ask the user for scope **only if it is ambiguous**. Sensible defaults (state them, then proceed):
   - Include: Markdown docs, README/CONTRIBUTING/CHANGELOG, `docs/**`, doc comments in source.
   - Exclude: generated files, `node_modules`/`vendor`/`target`/`dist`, third-party/licensed text, auto-generated API dumps.

---

## Phase 1 — Discovery

Find every candidate. Group results by type — this drives batching.

```bash
# Prose docs (primary targets)
rtk find "*.md" ; rtk find "*.mdx" ; rtk find "*.rst" ; rtk find "*.txt" ; rtk find "*.adoc"

# Well-known standalone docs
rtk grep -l "." README* CONTRIBUTING* CHANGELOG* ARCHITECTURE* 2>/dev/null

# Doc comments in source (report only; rewrite when the user opts in)
rtk grep -rn "///\|/\*\*\|\"\"\"\|^\s*#'" --include=*.rs --include=*.go --include=*.ts --include=*.py
```

Exclude the noise: `node_modules`, `vendor`, `target`, `dist`, `build`, `.git`, generated/minified files, and anything the user scoped out.

Produce a **manifest** — write it to `.claude/STE_MANIFEST.md`:

| # | File | Type | Approx. words | Batch |
|---|------|------|---------------|-------|
| 1 | README.md | prose | 1800 | A |
| 2 | docs/setup.md | prose | 600 | A |
| ... | | | | |

---

## Phase 2 — Batching

Balance batches so each subagent does roughly equal work and no two agents touch the same file.

- **~4–8 files or ~3000–5000 words per batch.** Split large files into their own batch.
- **One file is only ever in one batch** — no overlap, so agents never collide.
- Keep related files together (all of `docs/api/**` in one batch) so terminology stays consistent within a subsystem.
- Prose docs first. Doc comments in source code are a separate, opt-in pass (Phase 4) — they carry code-context risk.

---

## Phase 3 — Dispatch parallel rewriter subagents

Spawn one subagent per batch, **in a single message** so they run concurrently. Use the `general-purpose` (or `scribe`, if available) agent type.

Give each subagent this contract:

```
You are an STE rewriter. Rewrite the documentation files in your batch into
ASD-STE100 Simplified Technical English (Issue 9). Do not change meaning,
facts, code, commands, file paths, or API names — only the prose around them.

RULES: Read <repo>/skills/ste-docs/reference/asd-ste100-rules.md in full and
apply every rule. The essentials:
  - Approved words only, used only as their approved part of speech and meaning.
  - One meaning per word; use the SAME word for the same thing every time.
  - Active voice. One instruction per sentence in procedures.
  - Procedural sentences ≤ 20 words; descriptive sentences ≤ 25 words.
  - Simple verb tenses only. No gerunds-as-nouns, no synonyms, no idioms.
  - Paragraphs: one topic, topic in the first sentence, ≤ 6 sentences.
  - Warnings/cautions before the step, written as a clear command.

MUST NOT TOUCH:
  - Code blocks, inline code, commands, URLs, file paths, identifiers.
  - Front-matter keys, headings' anchor meaning, tables' data.
  - Proper nouns and product/technical names.

FILES: <list the batch's files>

OUTPUT: Edit each file in place. Then return a short per-file changelog:
what categories of change you made and any sentence you could not make STE-
compliant without risking meaning (flag these — do not guess).
```

**Terminology lock:** before dispatch, extract the project's key technical names (product names, command names, domain nouns) from the top-level README and pass that glossary to every agent. STE requires the same word for the same thing across the whole repo — a shared glossary prevents agents from diverging.

---

## Phase 4 — Doc comments in source (opt-in)

Only after prose docs are done, and only if the user wants it. Dispatch subagents the same way, but with an extra constraint:

```
Rewrite ONLY the text inside doc comments (///, /**...*/, docstrings).
Do not change code, signatures, examples, annotations, or comment syntax.
Keep the first line a short summary sentence. Never break doc-tooling tags
(@param, :returns:, # Arguments, etc.).
```

Compilers and doc generators are the safety net here — see Phase 5.

---

## Phase 5 — Verify

Nothing is "done" until it is proven. In the main thread, after agents return:

1. **Diff review:** `rtk git diff --stat` then spot-read the largest diffs. Confirm no code, commands, or paths changed.
2. **Docs still build / lint** (whichever the repo has):
   ```bash
   rtk npm run docs 2>/dev/null || rtk cargo doc --no-deps 2>/dev/null || true
   rtk npx markdownlint "**/*.md" 2>/dev/null || true
   ```
3. **Links intact:** check that no rename broke a relative link or anchor.
4. **STE self-check pass:** for a sample of rewritten files, apply the checklist in `reference/asd-ste100-rules.md` (§ Self-check). If a file fails, send it back to a subagent with the specific violations.
5. **Flagged sentences:** collect every "could not make compliant" flag the agents returned and resolve them with the user — do not silently leave or force them.

---

## Phase 6 — Report

Write `.claude/STE_REPORT.md`:

```markdown
# STE Rewrite Report

**Branch:** docs/ste-rewrite
**Date:** <date>
**Standard:** ASD-STE100 Issue 9 (January 2025)

## Scope
- Files rewritten: N prose, M doc-comment
- Files excluded: <list + reason>

## Change summary (by category)
- Non-approved words replaced: <count / top examples: "utilize"→"use", ...>
- Passive → active voice: <count>
- Sentences split (length rule): <count>
- Noun clusters simplified: <count>
- Terminology unified: <term → chosen form>

## Verification
- Docs build: PASS/FAIL/N-A
- Markdown lint: PASS/FAIL/N-A
- Links checked: PASS/FAIL

## Open questions / flagged sentences
1. `file:line` — <sentence that could not be made STE-compliant without risking meaning>

## Next step
Review the diff, then merge docs/ste-rewrite.
```

Then show the user the diff summary and the report. Commit only when the user asks (per repo rules), with their exact message.

---

## Anti-patterns

- Do NOT rewrite files inline in the main thread — always dispatch subagents.
- Do NOT change meaning, code, commands, paths, or API names to satisfy a rule. Flag it instead.
- Do NOT let two agents edit the same file — enforce non-overlapping batches.
- Do NOT invent "approved" words — the vocabulary is fixed; if unsure, keep the technical name or flag it.
- Do NOT translate the language of the docs. STE is a controlled form of English; if a doc is in another language, ask the user before touching it.
- Do NOT skip verification — a rewrite that breaks the doc build or a relative link is a regression.
