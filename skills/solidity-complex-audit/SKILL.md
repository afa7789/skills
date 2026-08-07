---
name: solidity-complex-audit
description: Full multi-phase Solidity audit engagement driven by scripts/solidity-audit.sh — host malware check, orientation read, multi-source finding discovery (one subagent per solidity-review check, plus Slither, Aderyn and a cross-vendor second opinion), consolidation and ranking, then one reproducing Foundry test per finding. Use for auditing a whole codebase and shipping exploit PoCs plus fixes, not for reviewing a PR diff. Triggers on "complex audit", "full solidity audit", "audit engagement", "reproduce the exploits", "build v2 with fixes", "/solidity-complex-audit".
version: 2.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [solidity, smart-contracts, security, audit, pipeline, foundry, exploit, evm]
    related_skills: [solidity-review, pr-review-pipeline, peer-review]
---

# Solidity Complex Audit

Drives `scripts/solidity-audit.sh` through four phases and owns the judgement
the script cannot make: what is a true positive, what earns an exploit PoC, and
when the engagement is actually finished.

**This skill consumes `solidity-review`.** Its `reference/checklist.md` is the
audit taxonomy — Phase 3 dispatches one subagent per check (`S01`…`S35`),
injecting that check's own section text into the prompt. Adding a check to the
checklist adds a discovery pass here; there is no second taxonomy to maintain.

> **The script executes. This skill decides.** Never run `all` and present the
> output as an audit — every phase has a gate.

---

## When to Use

A **whole-codebase engagement** with deliverables: exploit proof-of-concepts, a
severity-ranked finding set, and tests that prove each defect.

**Use `solidity-review` alone when** you are reviewing a PR or a single
contract and want a checklist report — that is a reading methodology, this is
an engagement pipeline.

**Not for:** Vyper/Yul, off-chain code, or live incident response.

---

## Prerequisites

| Tool | Needed by | Missing → |
|---|---|---|
| `opencode` | discovery, classify, reproduce, fix | **hard fail** |
| `jq` | classify | **hard fail** |
| `forge` | reproduce, fix, verify | **hard fail** |
| `claude` | second-opinion pass | warns, skips |
| `slither` | discovery | warns, skips |
| `aderyn` | discovery | warns, skips |

The script lives in the skills repo, not inside this skill directory, so resolve
it rather than assuming a path — never hardcode one:

```bash
SOLIDITY_AUDIT="${SOLIDITY_AUDIT:-$(command -v solidity-audit.sh 2>/dev/null)}"
[ -n "$SOLIDITY_AUDIT" ] || SOLIDITY_AUDIT="$(
  find "$HOME" -maxdepth 6 -name solidity-audit.sh -type f \
       -not -path '*/node_modules/*' 2>/dev/null | head -1
)"
[ -x "${SOLIDITY_AUDIT:-}" ] || {
  echo "solidity-audit.sh not found. Set \$SOLIDITY_AUDIT to its path." >&2
  exit 1
}
```

Export `SOLIDITY_AUDIT` once in your shell profile to skip the search.

---

## Phase 1 — Host safety

```bash
"$SOLIDITY_AUDIT" init <repo> --dry-run   # inspect the plan first
"$SOLIDITY_AUDIT" init <repo>
```

Statically inspects installers, packages and archives for install hooks and
lifecycle scripts, pipe-to-shell and obfuscated `eval` payloads, and path
traversal / symlinks in zips.

**Gate:** any indicator → **stop and report**. Never `--skip-malware` past a
real finding. The point of this phase is that nothing gets installed and no
host compromise goes unnoticed.

---

## Phase 2 — Orientation

Covered by `init`. A quick pass over the contracts and existing tests to build a
mental model. Do not start judging yet.

---

## Phase 3 — Discovery, from independent sources

```bash
"$SOLIDITY_AUDIT" scan <repo>
```

Six sources, deliberately independent so they fail differently:

| # | Source | Output |
|---|---|---|
| 3.1 | One opencode subagent **per `solidity-review` check**, each carrying that check's definition | `opencode-S<nn>.md` |
| 3.2 | `solidity-review` holistic pass (whole checklist at once — catches cross-check interactions) | `solidity-review.md` |
| 3.3 | `claude` second opinion (different vendor, different failure modes) | `claude.md` |
| 3.4 | Aderyn | `aderyn.md` |
| 3.5 | Slither | `slither.md` |

Scope with `--classes S02,S07,S14` when a full fan-out is too expensive — 35
parallel agent runs is real cost and real rate-limit pressure.

**Gate:** read the raw output. Discard anything without a concrete `file:line`.
Agreement across sources raises confidence; a finding only one source saw is not
thereby wrong, but it earns more scrutiny.

> **open-kritt is deliberately absent.** It is a self-hosted Docker + Node
> platform with a GUI, not a CLI, so it cannot be a pipeline step. Slither,
> Aderyn and the per-check fan-out cover the same ground headlessly. If you want
> another engine, add a headless CLI (e.g. Mythril) and drop its report into the
> findings dir — consolidation picks up any `*.md` there.

---

## Phase 3.8 — Consolidate and rank

```bash
"$SOLIDITY_AUDIT" classify <repo>
```

Parses every `## <ID> — <title>` heading in the findings dir into `raw.json`
(`N/A` sections are dropped), then runs three agents in parallel: semantic
dedupe → severity ranking → still-present verification against current code.
Outputs `deduped.json`, `ranked.json`, `patch-status.json`.

**Gate — the most important one.** Split every finding into:

- **True positive, exploitable** → goes to Phase 4
- **True positive, not exploitable** → report only, no PoC
- **False positive** → drop it, and record why

Never send an unclassified finding to `reproduce`.

---

## Phase 4 — Reproduce, fix, verify

```bash
"$SOLIDITY_AUDIT" reproduce <repo> --retries 2
"$SOLIDITY_AUDIT" fix <repo>
"$SOLIDITY_AUDIT" verify <repo> --report <path>
```

`reproduce` writes one test per confirmed finding and **loops**: if the suite
compiles but nothing fails, the tests prove nothing, so it re-dispatches with
the forge output and rewrites them, up to `--retries`. Exhausting the retries is
reported as *unconfirmed*, not as success.

**Gates:**

- A finding is confirmed only when its test **fails against v1 for the reason
  claimed**. A compile error, or a failure from an unrelated revert, is not a
  proof.
- Never weaken an assertion to force a failure. That is fabricated evidence.
- Every fix in v2 must trace to a confirmed finding — reject scope creep.
- `verify` runs the suite three times; all three must agree. 2-of-3 green is a
  flaky or state-dependent fix, so the finding stays open.

---

## Deliverables

- Findings dir with every source's raw output preserved
- A triage record: true positive / not exploitable / false positive, **with reasons**
- One reproducing test per confirmed-exploitable finding, failing against v1
- A v2 whose every change traces to a confirmed finding
- Three identical green runs against v2
- Findings graded by severity with `file:line`

If any is missing, say which and why. Never present a partial run as a finished
audit.

---

## Project Detection

Nothing is hardcoded to a particular codebase:

| Thing | How it is resolved | Override |
|---|---|---|
| Project root | nearest `foundry.toml` (ignoring `lib/`, `node_modules/`) | — |
| Contracts dir | `src/`, else `contracts/` under that root | `--src` |
| Tests dir | `test/`, else `tests/` | `--test` |
| Contract under test | largest `.sol` under `--src`, skipping interfaces (`I<Name>.sol`), mocks and `*V1.sol` | `--contract` |
| Checks | every `S<nn>` section in the `solidity-review` checklist | `--classes`, `--checklist` |

The `fix` phase reads `ranked.json` and `patch-status.json` — files this
pipeline actually produces — and is told to adopt the remediation idioms of
whatever libraries the project already imports, rather than to impose a
particular stack. Project-specific requirements go through
`--extra-requirement "<text>"`; reward bands, which are per-program, through
`--bounty-bands "<text>"` (omitted by default, so ranking is by exploitability
and blast radius alone).

## Known Sharp Edges

1. **`all` runs `fix`**, which mutates the tree. Commit or worktree first.
2. **Contract auto-detection picks one contract** — the largest. On a
   multi-contract system, pass `--contract` per run, or drive `fix` yourself.
3. **Phase 1 is static-only.** Credential exfiltration and persistence are named
   in the audit spec but not automated; inspect CI configs and deploy scripts by
   hand.

---

## Escalate to the User

- Any Phase 1 indicator — immediately
- A finding implying funds at risk in already-deployed code
- A fix requiring a storage-layout change on an upgradeable contract
- Before a full 35-check fan-out on a large codebase (cost)
- Retries exhausted without reproduction — the findings are unconfirmed
