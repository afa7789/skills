---
name: summarize
description: "Summarize and audit documents or project status the user points at (plans, specs, notes, .claude/, md/yaml/json/pdf) plus dagRobin progress. Writes SUMMARY.md: status, doc-vs-code drift, open items, stale files. Triggers on \"summarize these docs\", \"what's the status\", \"audit the plans\"."
---

# Summarize

Read-only. The one write is `SUMMARY.md` (repo root unless the user names a path).

Host can run this as a subagent on a small, cheap model → do that. Pass it the paths and this file. In Claude Code use `subagent_type: general-purpose` with `model: haiku`. `Explore` has no Write tool, so it cannot write `SUMMARY.md`.

## Input

- Exactly the paths and globs the user names. Any type: md, txt, yaml, json, `.claude/`, plans, specs, notes. PDFs via page reads, max 20 pages per read.
- `.dagrobin/` found (walk up from cwd) → `dagRobin status` and `dagRobin list --format json`.
- Nothing named → dagRobin only, if present. Otherwise ask which files.
- Never sweep the whole repo unasked. For doc-vs-code drift, open only the code a document names (paths, symbols, commands).
- Never run `dagRobin verify`, `claim` or `update`: they write.

## SUMMARY.md

```markdown
# Summary: <scope> (<date>)

## Status
done N · in progress N · open N   (dagRobin counts; else counted from the docs)

## Documents
- `<path>`: <what it is>. <state: current | draft | done | superseded>.

## Drift
- `<a.md>:<line>` says X; `<b.md | src/x.ts>:<line>` says Y. <which is right, when code settles it>

## Open items / next actions
- [ ] <item> (`<source>:<line>`)

## Stale or superseded
- `<path>`: <superseded by `<path>` | references missing files | all tasks done>. Suggest: archive | delete.
```

## Rules

1. Per document 2–3 lines. Keep facts, cut words.
2. Every drift item cites `file:line` on both sides. No citation → not drift.
3. Never delete, move or edit any other file. Suggest only.
4. Empty section → `none`.
5. Reply in chat with the path of `SUMMARY.md` and the top 3 open items.
