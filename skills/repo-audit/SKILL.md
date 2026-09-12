---
name: repo-audit
description: Parallel audit in two modes. FULL mode splits the whole repository into 9 balanced scopes; DIFF mode audits only a PR, branch or ref range plus its blast radius. Both dispatch background subagents and consolidate every finding into one machine-readable YAML (schema v1.0) for other agents to filter, order and plan from. Deletion-first — every abstraction must pay rent. Language, framework and architecture agnostic. Standalone, or callable as a stage by review/planning pipelines. Trigger with "audit the repo", "repository audit", "does this PR over-engineer", "audit this diff", "find over-engineering", "what can we delete", "/repo-audit", "/repo-audit --diff <base>".
---

# Repo Audit — parallel scopes → one YAML of findings

Produces **structured data about the state of the code**, not an editorialized refactor plan. No "Top 10". No prose summary. One YAML artifact.

## Two modes

| Mode | Audits | Agents | Output |
|---|---|---|---|
| **FULL** (default) | The whole repository | exactly 9 | `.claude/AUDIT.yaml` |
| **DIFF** | One PR / branch / ref range, plus its blast radius | 3–9, scaled to diff size | `.claude/AUDIT_DIFF.yaml` |

Pick DIFF when the user names a PR, a branch, a ref range, "this diff", "these changes", or asks whether a change over-engineers something. Pick FULL otherwise. When ambiguous and a feature branch is checked out, ask which one.

Both modes share the same playbook, the same schema, and the same deletion-first principle. Only the scope and the attribution rule differ.

Two reference files, both required reading before dispatch:

- [`reference/detection-playbook.md`](reference/detection-playbook.md) — the 19 detection techniques, the deletion-first ladder, the heuristics, the anti-cosmetic rule.
- [`reference/finding-schema.md`](reference/finding-schema.md) — the YAML schema v1.0 and the enum rules (`category`, `severity`, `priority`, `status`, `change_type`).

Nothing here is repo-, language-, framework- or branch-specific. Scopes are derived from the actual repository structure at runtime.

---

## ⚠️ Hard requirement — REAL background subagents

All `Agent` tool calls dispatched **in one message** so they run concurrently in background — 9 in FULL mode, 3–9 in DIFF mode. The main thread only scopes, dispatches, consolidates, emits. Do NOT audit inline. If the `Agent` tool is unavailable, STOP and tell the user.

---

## Central principle — deletion first

**Every abstraction must pay rent.** The ladder, the justifications that count and the
ones that do not are in [`reference/detection-playbook.md`](reference/detection-playbook.md),
which both the main thread and every subagent read in full before any dispatch.

---

## Phase 0 — Orient

0. **Determine the mode.** A PR number, branch, ref range, "this diff" or "these changes" in the request → DIFF mode, go to Phase 1D after this phase. Otherwise FULL mode, go to Phase 1. State the chosen mode and the resolved `base...head` before dispatching anything.
1. `rtk git status` — note the working tree state. This audit **reads only**; it changes no code.
2. Map the repository shape yourself — do not assume a layout:
   ```bash
   rtk ls .
   rtk find "package.json" ; rtk find "Cargo.toml" ; rtk find "go.mod" ; rtk find "pyproject.toml"
   ```
   Read the build/workspace manifests, the top-level README, and any `docs/` index. Identify languages, package boundaries, entry points, and which directories carry real weight.
3. Exclude from scope: `node_modules`, `vendor`, `target`, `dist`, `build`, `.git`, lockfiles, generated code, third-party vendored source. Record exclusions — they go in `audit_coverage.excluded_paths`.

---

## Phase 1 — Derive exactly 9 scopes

Decide the split from the real structure. Each scope must be:

- **independent enough** — an agent can reason about it without constantly reading another scope;
- **roughly balanced** in size and complexity (weight by files × complexity, not file count alone);
- **semantically coherent** — a subsystem, a package, a layer, or a cross-cutting concern, not an alphabetical slice;
- **non-overlapping** beyond what is unavoidable at boundaries.

Natural axes, in rough order of preference — pick whichever the repo actually exhibits, or mix them:

| Axis | Fits |
|---|---|
| Package / workspace member | Monorepos |
| Deployable unit or service | Multi-service repos |
| Domain / bounded context | Domain-heavy single apps |
| Layer (transport, domain, data, UI) | Layered single app |
| Cross-cutting concern (config + env, dependencies + build, tests, docs vs. code, types/contracts) | Always useful for 1–3 of the 9 slots |

Reserve at least one scope for cross-cutting surfaces the per-directory split would otherwise miss — typically **configuration + environment variables + feature flags**, and **documentation vs. implementation**.

Write the split to `.claude/AUDIT_SCOPES.md` (agent number → scope description → paths → why this boundary). This becomes `audit.scope.scopes` in the output.

**Model choice:** pick per agent. Dense architectural scopes and cross-cutting reasoning warrant the stronger model; mechanical sweeps (dead exports, unused config keys, dependency hygiene) run fine on a cheaper one. State the choice in the scopes file.

---

## Phase 1D — DIFF mode: scope from the change

Run this **instead of** Phase 1 when in DIFF mode.

### Resolve the range

```bash
# PR number given
gh pr view <n> --json baseRefName,headRefName,title,body
# branch or explicit range given
rtk git merge-base HEAD <base>     # never eyeball the branch point
rtk git diff --stat <base>...HEAD
rtk git log --oneline <base>..HEAD
```

Record `base`, `head`, and the commit subjects — the commit messages and the PR body state the **intent**, and a finding needs intent to judge whether an abstraction pays rent.

### Build the blast radius

The diff alone is not enough scope. An added interface is only over-engineering if you know how many implementations and consumers exist — and those live outside the diff.

For every symbol added, renamed or changed in the diff, find its call sites, implementations and consumers across the whole repo. Include those files as **read-only context**, marked as such. Also pull in: the config/env files the diff touches, the tests covering the changed symbols, and any documentation naming them.

```bash
rtk git diff --name-only <base>...HEAD      # changed files
rtk grep -rn "<added symbol>"               # consumers, per symbol
```

### Split into 3–9 scopes

Use as many agents as the change has coherent scopes — around 3 for a small diff, up to 9
for a large one — and always reserve one for the cross-cutting pass over the whole diff
(the surfaces listed for FULL mode in Phase 1).

Split by the same axes as FULL mode (package, service, domain, layer).

Write the split to `.claude/AUDIT_SCOPES.md` as in FULL mode, recording `base`, `head`, and which files are in-scope vs. read-only context.

### Attribution rule — what counts as a finding

A DIFF-mode finding must be attributable to the change. The Phase 2 contract states the
rule for the agent that applies it, and `reference/finding-schema.md` defines the
`pre_existing` field that records it. Here the main thread needs only one consequence:
report counts split by `pre_existing`, so a consumer can read "what this change
introduced" straight off the summary.

---

## Phase 2 — Dispatch the subagents

One message, N `Agent` calls (9 in FULL, 3–9 in DIFF), `run in background`. Contract for each:

```
You audit ONE scope of this repository. Read-only: you change no files.

MODE: FULL | DIFF
SCOPE: <paths + description + explicit out-of-scope note>
  DIFF mode only:
    BASE...HEAD: <range>
    IN-SCOPE (changed by the diff): <files>
    READ-ONLY CONTEXT (blast radius — never report findings against these
      unless the diff made them dead or contradicted them): <files>
    CHANGE INTENT (commit subjects + PR body): <text>

REQUIRED READING (read both in full before you start):
  <repo>/skills/repo-audit/reference/detection-playbook.md
  <repo>/skills/repo-audit/reference/finding-schema.md

The current code is the source of truth for implemented behavior. Documentation
describes it; only the code decides it.

REQUIRED READING (both in full, before you start — they carry the techniques, the
deletion-first ladder, the evidence bar, the anti-cosmetic rule and every enum you
will write):
  <repo>/skills/repo-audit/reference/detection-playbook.md
  <repo>/skills/repo-audit/reference/finding-schema.md

Apply them exactly as they state them. Nothing below repeats their content; it
orders the work and bounds it.

WORK, in order, over your scope:
 1. Map the flows and the responsibilities.
 2. Walk all 19 detection techniques against that map, technique by technique.
 3. For each candidate, gather the evidence the schema demands before writing it
    up — call sites, imports, exports, tests, config, or verifiable absence of
    consumers. A candidate you cannot evidence is a candidate you drop.
 4. Where something looks suspicious and turns out justified, write it up with
    change_type: "retain" so a later agent leaves it alone.

REPORT every relevant improvement, not only simplification: the schema's category
enum is the full range you are hunting.

DONE when every one of the 19 techniques has been applied to every in-scope path,
and each finding carries a location plus evidence a reader can check without
trusting you. Name any technique you could not apply, and why, in
audit_coverage.limitations.

IN DIFF MODE, ADDITIONALLY:
 - Attribute every finding to the change: it qualifies when the diff introduces the
   problem, worsens it, fails to remove something its own change made dead, or
   contradicts something outside it (docs, types, contracts, tests).
 - Pre-existing complexity the diff sits near belongs in the report as
   severity: informational, status: needs_investigation, labelled pre-existing.
   Set pre_existing on every finding either way.
 - Judge each abstraction the diff ADDS by the implementations and consumers that
   exist once it lands. One implementation and one consumer is a finding.
 - Read the change intent before calling a boundary unjustified: intent is what
   decides whether it pays rent.

OUTPUT: a single valid YAML document following finding-schema.md, containing
ONLY your `findings:` list plus an `audit_coverage:` block for your scope.
Ids namespaced to your agent number: "A3-001", "A3-002", ...
No prose outside the YAML block.
```

---

## Phase 3 — Consolidate

In the main thread, once every dispatched agent returns:

1. **Aggregate** every finding.
2. **Deduplicate** — identical findings collapse to one.
3. **Merge** equivalent findings, preserving the union of their evidence and locations.
4. **Preserve concrete evidence** — never drop a citation while merging.
5. **Resolve conflicts** between agents where the code settles it; where it does not, record a `conflicts:` entry with both positions and `requires_human_review: true`.
6. **Do not promote speculation to fact.** Insufficient evidence → `status: needs_investigation`, or an `unresolved:` entry.
7. **Do not narrow to simplification.** Every category in the schema is in play.
8. **Lift cross-cutting causes.** When several findings are symptoms of one structural cause (three competing representations of a domain, a repeated no-op wrapper pattern, an incomplete migration spread across the repo, config duplicated across services), create a `cross_cutting_findings:` entry and reference the symptoms in `affected_findings` instead of repeating the same recommendation dozens of times.
9. **Wire relations.** Fill `blocked_by` / `blocks` / `related_findings` so a later agent can build an execution DAG.
10. **Renumber** to sequential `AUDIT-001…`, keeping a map from the agent-local ids so relations survive.
11. **Recount** `summary.total_findings`, `by_severity`, `by_category` from the final list — never from the agents' own counts.

---

## Phase 4 — Emit

Write `.claude/AUDIT.yaml` (FULL mode) or `.claude/AUDIT_DIFF.yaml` (DIFF mode) — separate files, so a diff audit never overwrites a repo audit. It must be **valid, machine-readable YAML following schema v1.0 exactly** — no introduction, no conclusion, no Markdown outside the document.

Verify before finishing:

```bash
python3 -c "import yaml; yaml.safe_load(open('.claude/AUDIT.yaml'))" && echo VALID
```

Then check: every enum value is legal; every finding has ≥1 location and ≥1 concrete evidence item; counts match the list; every id referenced in `blocked_by`/`blocks`/`related_findings`/`affected_findings` exists; unknowns are `null`, not invented; paths are relative to the repo root; single elements still use arrays. In DIFF mode also: `scope.mode`, `scope.base` and `scope.head` are set, and every finding carries `pre_existing`.

To the user, print only: the path to the YAML, the scopes, and the counts by severity and category — in DIFF mode, split those counts by `pre_existing`. The data is the deliverable.

---

## Use as a stage in another pipeline

`.claude/AUDIT.yaml` is the contract. Two callers consume it today:

- `multi-agent-loop` imports findings as dagRobin tasks, filtered to `status: actionable` + `confidence: high` + `priority in {immediate, high}` + `change_type != retain`.
- `pr-review-pipeline` (and `multi-agent-loop`'s DIFF-mode variant) filters `pre_existing: false` for "what this PR introduced" and folds `severity in {critical, high}` into Blocking Issues.

Callers pass scope overrides and read the YAML; they never re-parse prose.

---

## Anti-patterns

- An agent count that does not match the mode (9 in FULL), or agents run in the foreground one at a time.
- Scopes split alphabetically or by directory listing order instead of by meaning.
- A finding whose evidence is an opinion.
- Severity used as priority, or priority used as confidence.
- Inventing metric numbers instead of `null`.
- Producing a ranked editorial summary instead of the data.
- Deleting an abstraction that pays rent because a heuristic flagged it.
