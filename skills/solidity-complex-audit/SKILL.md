---
name: solidity-complex-audit
description: Full multi-phase Solidity audit engagement: discovery across independent sources, consolidation, then one reproducing Foundry test per finding.
version: 2.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [solidity, smart-contracts, security, audit, pipeline, foundry, exploit, evm]
    related_skills: [solidity-review, pr-review-pipeline, peer-review]
disable-model-invocation: true
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

Hard-fail without `opencode`, `jq` and `forge`; `claude`, `slither` and
`aderyn` are optional and skip with a warning if missing. Run
`solidity-audit.sh help` for the full tool, flag and default list.

The script lives in the skills repo, at `scripts/solidity-audit.sh`, not
inside this skill directory:

```bash
SOLIDITY_AUDIT="${SOLIDITY_AUDIT:-scripts/solidity-audit.sh}"
[ -x "$SOLIDITY_AUDIT" ] || {
  echo "solidity-audit.sh not found at '$SOLIDITY_AUDIT'. Export \$SOLIDITY_AUDIT to its path (scripts/solidity-audit.sh in the skills repo)." >&2
  exit 1
}
```

Export `SOLIDITY_AUDIT` once in your shell profile if this skill runs from
somewhere other than the skills repo root.

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

## Phase 2.5 — Static project map

```bash
"$SOLIDITY_AUDIT" map <repo>
# or standalone:
scripts/solidity-map <repo> --output findings/map.json
```

Before any LLM work, classify every `.sol` (and config artifact) into a
small taxonomy — zero LLM cost, and well under a second once
`scripts/solidity-map` is built (`solidity-audit.sh map` builds it
automatically from `scripts/solidity-map.go`, stdlib only, on first use if
`go` is installed). The rest of the pipeline scopes itself
against this map; on a 200-file codebase, fan-out checks against files
that are obviously OpenZeppelin noise is wasted tokens.

**Taxonomy:** the 14 categories and their classification rules are the
`Cat*` constants and switch in `scripts/solidity-map.go` — the binary
produces the map, the agent never applies these rules itself; read
`findings/map.json` for the classified output. The audit implication of
each category, which the Go file does not carry:

| Category | Audit implication |
|---|---|
| `core` | Primary audit targets |
| `interface` | Read-only contracts; cheap, check event/method parity |
| `library` | Internal functions; review for unchecked inputs |
| `abstract` | Inherited — review what *concretises* them |
| `mock` | Skip in production audit; useful only for test-harness review |
| `deploy_script` | Review constructor args + access control on broadcast caller |
| `test` | Standard test coverage |
| `invariant` | Invariant properties — high-signal; rarely enough |
| `fuzz` | Fuzz coverage; check invariants they assert |
| `external` | Skip unless pinning a known-vulnerable version |
| `oracle` | Apply S21 / S22 explicitly even if overall review is shallow |
| `keeper` | Apply S27 (`block.timestamp`) strictly |
| `proxy` | Apply S26 + storage-layout check; `--classes` should keep S26 |
| `config` | Review chain IDs, RPC URLs, deployer keys (S18) |

Each part also carries `kind` tags (`payable`, `upgradeable`, `owned`),
`external_deps` (import targets outside the repo), and `contracts` (every
top-level declaration found).

**Gate:** the map is *information*, not judgement. Read the summary line
(`total parts: N | core: N | external: N | deploy: N | invariant: N |
fuzz: N`) before dispatching subagents. If `external` dominates, scope
the discovery to `src/` only. If there is no `invariant` and no `fuzz`,
flag that — the test suite will not catch the S01/S20/S34-style bugs.

> **Re-run is idempotent.** If `findings/map.json` exists, `map` skips.
> Delete it to force a rebuild after a large merge.

---

## Phase 3 — Discovery, from independent sources

```bash
"$SOLIDITY_AUDIT" scan <repo>
```

Five sources, deliberately independent so they fail differently:

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

> To add another engine, run any headless CLI (e.g. Mythril) and drop its
> report into the findings dir — consolidation picks up every `*.md` there.

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

> **Instinct overruled too early is the most expensive mistake.** When the
> ranker or patch-check subagent says "needs_manual_review" or marks a finding
> non-exploitable, the discovery instinct was probably right — only the PoC
> attempt failed. Before classifying anything as false positive, run **one more
> pass** with a targeted prompt: "previous agent concluded X; try a different
> exploit vector, set up different pre-state, or attack a different caller."
> The `reproduce` phase enforces this loop with its retry budget; the
> classify gate enforces it on the triage side. If after one extra pass the
> PoC still does not land, *then* drop it — and record both attempts in
> `findings/disposition.json` so the false-positive call is auditable.

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
- **No silent drops.** Findings the pipeline could not reproduce are not
  "closed" — they are carried into `findings/disposition.json` as `unconfirmed`
  with the *exact* forge output and a one-line reason. The `fix` phase reads
  that list and must either (a) apply a preventive fix anyway, or (b) cite
  the manual evidence that the finding is benign. Either choice is recorded
  in `findings/v2-disposition.json`. **A submission that leaves unconfirmed
  Critical/High findings without a preventive fix is not deployable:**
  documenting the bug is not enough; either fix it or back the false-positive
  call with reproducible evidence of benignity.

---

## Deliverables

- `findings/map.json` — every `.sol` categorised, external deps, kind tags,
  Foundry layout. Run `map` first on large codebases; on small ones it is
  still cheap and tells you what you are about to spend tokens on.
- Findings dir with every source's raw output preserved
- A triage record: true positive / not exploitable / false positive, **with reasons**
- `findings/disposition.json` listing every finding's final call and the
  evidence backing it (PoC test path, or manual evidence, or unconfirmed with reason)
- One reproducing test per confirmed-exploitable finding, failing against v1
- A v2 whose every change traces to a confirmed finding (or to a preventive
  fix on an unconfirmed Critical/High — `v2-disposition.json` records which)
- Three identical green runs against v2
- Findings graded by severity with `file:line`

If any is missing, say which and why. Never present a partial run as a finished
audit.

---

## Project Detection

Nothing is hardcoded to a particular codebase — project root, contracts/tests
dirs, contract under test, project map and checks are all auto-detected with
an override flag; run `solidity-audit.sh help` for the resolution rules and
flags.

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
