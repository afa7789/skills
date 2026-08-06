---
name: solidity-complex-audit
description: Full multi-phase Solidity audit engagement driven by scripts/solidity-audit.sh — malware check, parallel finding discovery, dedupe and ranking, exploit reproduction with Foundry tests, a fixed v2 build, and triple-run verification. Use for auditing a whole codebase and shipping exploit PoCs plus fixes, not for reviewing a PR diff. Triggers on "complex audit", "full solidity audit", "audit engagement", "reproduce the exploits", "build v2 with fixes", "/solidity-complex-audit".
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [solidity, smart-contracts, security, audit, pipeline, foundry, exploit, evm]
    related_skills: [solidity-review, pr-review-pipeline, peer-review]
---

# Solidity Complex Audit

Drives `scripts/solidity-audit.sh`, a 4-phase reproducible audit pipeline, and
owns the judgement the script cannot make on its own: deciding what is a true
positive, what gets an exploit PoC, what gets fixed, and when the engagement is
actually done.

> **The script executes. This skill decides.** Never run `all` and hand the
> output over as an audit — every phase has a gate that needs a human or agent
> call before the next one is worth running.

---

## When to Use

Use this skill when the ask is a **whole-codebase engagement** with deliverables:

- Auditing an unfamiliar Solidity repo end to end
- Producing exploit proof-of-concepts, not just a list of concerns
- Shipping a fixed v2 alongside the findings
- Re-verifying that fixes hold across repeated test runs

**Use `solidity-review` instead when:** you are reviewing a PR, a diff, or a
single contract and want a severity-graded checklist report. That skill is a
reading methodology; this one is an engagement pipeline. They are independent —
this skill does not consume the `S01–S35` checklist.

**Don't use either for:** Vyper/Yul, off-chain code, or live incident response.

---

## Prerequisites

The script fails fast on missing hard dependencies. Check before starting:

| Tool | Needed by | Install |
|---|---|---|
| `opencode` | discovery, classify, reproduce, fix | https://opencode.ai |
| `python3` | classify, reproduce | system |
| `forge` | reproduce, fix, verify | https://book.getfoundry.sh |
| `slither` | discovery (optional, warns) | `pipx install slither-analyzer` |
| `aderyn` | discovery (optional, warns) | https://github.com/Cyfrin/aderyn |

Locate the script before anything else — it lives in the skills repo, not
inside this skill directory:

```bash
SOLIDITY_AUDIT="$HOME/Developer/arthur/LLM/skills/scripts/solidity-audit.sh"
[ -x "$SOLIDITY_AUDIT" ] || { echo "solidity-audit.sh not found or not executable"; exit 1; }
```

If it is missing, stop and say so. Do not reimplement the pipeline inline.

---

## Command Surface

```
solidity-audit.sh <command> <repo-path> [options]

init       Phase 1 + 2   malware check, then orientation read
scan       Phase 1 + 3   malware check, then discovery passes
classify   Phase 3.8     dedupe + rank + patch-history
reproduce  Phase 4.2     write ExploitV1 tests and run them
fix        Phase 4.4     build v2 with true-positive fixes
verify     Phase 4.8     3-run forge test verification
all                      every phase, end to end
```

Options that matter in practice:

| Option | Use it when |
|---|---|
| `--src <path>` | The contracts are not in `<repo>/market/src` (**usually**) |
| `--test <path>` | Tests are not in `<repo>/market/test` |
| `--findings <path>` | You want findings outside `<repo>/findings` |
| `--classes <list>` | You want to scope discovery — see the caveat below |
| `--skip-malware` | The repo is trusted source you already vetted |
| `--worktree <path>` | Reuse an existing worktree instead of a git mv |
| `--dry-run` | **Always, the first time against a new repo** |
| `--report <path>` | Default is `/tmp/v2-build-report.md`, which is volatile |

---

## Known Sharp Edges

Read these before the first run. They are properties of the current script, not
things to fix mid-engagement:

1. **Discovery classes are undefined.** The default `--classes L01..L25` are bare
   labels. The prompt template still contains the literal placeholder
   `<describe this class, severity default, what to look for>`, so each of the 25
   parallel subagents is asked to audit a class nobody defined. Treat Phase 3
   output as **unstructured leads, not a taxonomy**. If you want scoped
   discovery, pass your own meaningful `--classes` list.
2. **`LendingMarket.sol` is hard-coded** in the discovery prompt. On any other
   codebase that instruction is wrong; expect the subagents to drift.
3. **Layout assumptions.** Defaults are `<repo>/market/src` and
   `<repo>/market/test`. Pass `--src`/`--test` explicitly on anything else.
4. **Phase 3 fans out 25 background `opencode` runs at once.** That is real cost
   and real rate-limit pressure. Scope with `--classes` on large repos.
5. **`all` runs `fix`**, which modifies the codebase. Never run `all` against a
   repo whose working tree you have not committed or worktree'd first.

---

## Workflow

Run phase by phase. After each, apply the gate before continuing.

### 1. Orientation — `init`

```bash
"$SOLIDITY_AUDIT" init <repo> --dry-run       # inspect the plan first
"$SOLIDITY_AUDIT" init <repo> --src <path>
```

Phase 1 scans for install hooks in `package.json`, pipe-to-shell and `eval`
patterns, and path-traversal/symlink entries in zips. Phase 2 does an
orientation read.

**Gate:** if the malware check reports indicators, **stop**. Investigate each
one by hand and report to the user before touching anything else. Do not
`--skip-malware` past a real finding.

### 2. Discovery — `scan`

```bash
"$SOLIDITY_AUDIT" scan <repo> --src <path> --classes <your-list>
```

Writes one file per class to the findings dir, plus `slither.md` and
`aderyn.md` when those tools exist.

**Gate:** read the raw output yourself. Given sharp edge #1, expect noise,
duplicates and N/A-heavy files. Discard anything without a concrete
`file:line`.

### 3. Triage — `classify`

```bash
"$SOLIDITY_AUDIT" classify <repo>
```

Consolidates into `raw.json`, dedupes, ranks, and cross-references patch
history.

**Gate — the most important one.** Split findings into:

- **True positive, exploitable** → goes to `reproduce`
- **True positive, not exploitable** → report only, no PoC
- **False positive** → drop it, and note why in the report

Never send an unclassified finding to `reproduce`; you will spend a Foundry
test-writing cycle proving nothing.

### 4. Proof — `reproduce`

```bash
"$SOLIDITY_AUDIT" reproduce <repo> --test <path>
```

Writes `ExploitV1` tests and runs them.

**Gate:** a finding is only confirmed when its exploit test **fails against v1
for the reason claimed**. A test that fails to compile, or fails for an
unrelated revert, is not a proof — fix the test or demote the finding.

### 5. Remediation — `fix`

```bash
"$SOLIDITY_AUDIT" fix <repo> --reserve-factor   # flag is Compound-v2 specific
```

Builds v2 with fixes for the confirmed true positives.

**Gate:** every fix must map to a confirmed finding. Reject scope creep —
refactors that no finding motivated do not belong in an audit v2.

### 6. Verification — `verify`

```bash
"$SOLIDITY_AUDIT" verify <repo> --report <path>
```

Runs `forge test` three times.

**Gate:** all three runs must pass **identically**. A test that passes 2 of 3 is
a flaky or state-dependent fix — treat it as unresolved, not as done. Every
`ExploitV1` test must now fail to exploit.

---

## Deliverables

An engagement is complete when all of these exist:

- Findings dir with the raw per-class output preserved
- A triage record: each finding marked true positive / not exploitable / false
  positive, **with the reason**
- An `ExploitV1` test per confirmed-exploitable finding, failing against v1
- A v2 whose changes each trace back to a confirmed finding
- Three identical green `forge test` runs against v2
- The report at `--report`

If any one is missing, say which and why. Do not present a partial pipeline run
as a finished audit.

---

## Escalate to the User

- Malware indicators in Phase 1 — always, immediately
- A finding that implies funds are at risk in already-deployed code
- A fix that requires a storage-layout change on an upgradeable contract
- Discovery cost: before fanning out 25 subagents on a large codebase
