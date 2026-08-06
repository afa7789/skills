---
name: solidity-review
description: Use when reviewing Solidity/EVM smart contract changes. Systematic 29-check security audit with severity report.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [solidity, smart-contracts, security, audit, review, web3, evm]
    related_skills: [pr-review-pipeline, peer-review]
---

# Solidity Smart Contract Review

Systematic security and correctness review for Solidity / EVM smart contracts. Applies 29 known vulnerability patterns and beginner-mistake categories against a contract diff or full source tree, then emits a severity-graded audit report.

> **Trigger phrases:** "review solidity", "audit smart contract", "check this contract", "review .sol", "solidity security review", "audit this PR (solidity)"

> Source content adapted from *20 Common Solidity Beginner Mistakes* (RareSkills) and extended with advanced vulnerability classes (oracle manipulation, flash loans, insecure randomness, signature replay, forced ether, etc.).

---

## When to Use

- Reviewing a PR that touches `.sol` files
- Auditing a new contract before deployment
- Reviewing a single `.sol` file or a Foundry/Hardhat project
- Generating a security checklist report from a diff
- Pre-deployment hardening pass on a contract

**Don't use for:**
- Non-Solidity EVM code (Vyper, Yul) — different patterns
- Off-chain TypeScript/Rust — that's a normal code review
- Already-deployed mainnet incident response (use an incident playbook, not a checklist)

---

## Inputs

| Input | Source | Required |
|-------|--------|----------|
| Target | PR number, branch, file path, or contract name | yes |
| Solidity version | From `pragma` or `foundry.toml` / `hardhat.config.*` | auto |
| Scope | `.sol` files in diff, or all `.sol` in project | auto |

If invoked with a PR/branch, run the same Phase 0 (context resolution) as `pr-review-pipeline`, but scope the diff to `*.sol`.

---

## Workflow

### Phase 1 — Establish Scope and Context

Determine what to review:

```bash
# If PR/branch:
rtk git diff origin/<base>...HEAD -- '*.sol'

# If file or directory:
find . -name '*.sol' -not -path '*/node_modules/*' -not -path '*/lib/*'
```

Capture:
- Solidity pragma version (must be pinned for deployable contracts — see Check S11)
- Compiler optimizer settings (from `foundry.toml` / `hardhat.config.*`)
- Inherited interfaces and dependencies (OpenZeppelin version, etc.)
- Existing test coverage (look for `test/` or `src/test/`)

### Phase 2 — Read Full Files, Not Just Diffs

For each `.sol` file in scope:
1. Read the entire file — context outside the diff matters for storage layout, inheritance, and modifiers.
2. Note the contract's `pragma`, imports, inheritance chain, and `using ... for` declarations.
3. List every external/public function and classify it: state-modifying, view, pure, payable.

**Completion criterion:** every modified file has been read end-to-end with its contract structure summarized.

### Phase 3 — Apply the 29 Checks

Walk the checklist in the order below. For each finding, record:
- **Check ID** (e.g. `S07`)
- **Severity** (Critical / High / Medium / Low / Informational)
- **Location** (`file:line`)
- **Pattern observed** (the vulnerable code, copied)
- **Recommendation** (the fix, with corrected snippet if non-obvious)

Use `reference/checklist.md` for full vulnerable-vs-corrected examples per check. Use `reference/severity-matrix.md` for grading rules.

**Completion criterion:** every check has a Pass / N/A / Finding verdict. No silent skips.

### Phase 4 — Run Tooling When Available

If any of these are present, run them and fold results into the report:

```bash
# Slither (static analysis — covers many checks automatically)
slither . --filter-paths "node_modules|lib/" 2>/dev/null

# Mythril (symbolic execution)
myth analyze <Contract>.sol

# Foundry invariants (if foundry project)
forge build && forge test
```

Note: Slither does NOT detect `tx.origin` (S04), insecure randomness (S23), signature replay (S28), or forced ether (S29) — those require manual review. Do not skip Phase 3 just because Slither is green.

### Phase 5 — Emit Report

Write `SOLIDITY_REVIEW.md` next to the reviewed code, or print to terminal if the user has no project root. Follow the format in `reference/report-template.md`.

**Completion criterion:** report contains (a) summary counts by severity, (b) every Critical/High with a PoC sketch, (c) the full 29-check verdict table.

---

## The 29 Checks — Quick Reference

Default severity classes below; full descriptions and code examples in `reference/checklist.md`.

### Beginner-Mistake Class (S01–S20)

| ID | Title | Default | Tool-detected? |
|----|-------|---------|----------------|
| S01 | Division before multiplication | Low | Slither |
| S02 | Check-Effects-Interaction / reentrancy | High | Slither |
| S03 | `transfer()` / `send()` gas-stuffing | Medium | Slither |
| S04 | `tx.origin` for auth | High | Manual |
| S05 | Non-`safeTransfer` ERC-20 | High | Manual |
| S06 | `SafeMath` on Solidity ≥ 0.8.0 | Info | Manual |
| S07 | Missing access control | High | Manual |
| S08 | Expensive ops in unbounded loops | High | Manual |
| S09 | Missing input validation | Medium | Manual |
| S10 | Incomplete business logic | High | Manual |
| S11 | Unpinned pragma (`^0.8.0`) | Low | Manual |
| S12 | Inconsistent style / NatSpec | Info | formatter |
| S13 | Missing or mis-indexed events | Low | Manual |
| S14 | Missing unit tests | Medium | CI gate |
| S15 | Rounding in wrong direction | Medium | Manual |
| S16 | No formatter (`forge fmt`) | Info | formatter |
| S17 | `_msgSender()` without meta-tx support | Info | Manual |
| S18 | Secrets committed to git | High | gitleaks |
| S19 | No frontrunning / slippage guards | Medium | Manual |
| S20 | Overwrite instead of accumulate (`=` vs `+=`) | High | Manual |

### Advanced Class (S21–S29)

| ID | Title | Default | Tool-detected? |
|----|-------|---------|----------------|
| S21 | Price oracle manipulation | Critical | Manual |
| S22 | Flash loan amplification | Critical | Manual |
| S23 | Insecure randomness | High | Manual |
| S24 | DoS via gas-limit on unbounded loops | High | Manual |
| S25 | Unchecked low-level external calls | High | Slither |
| S26 | `delegatecall` storage collision | Critical | Slither |
| S27 | Critical logic on `block.timestamp` | Medium | Manual |
| S28 | Signature replay | High | Manual |
| S29 | Forced ether breaks `address(this).balance` assumptions | Medium | Manual |

---

## Severity Grading

Default severities are above; adjust per context:

- **Critical:** direct loss of user funds, full contract compromise, or unstoppable drain. Blocks merge.
- **High:** exploitable under realistic conditions; significant fund loss or invariant break. Blocks merge.
- **Medium:** exploitable only with specific conditions (admin key compromise, specific state); or significant DoS / logic bug. Should fix before merge.
- **Low:** code-quality / gas / best-practice issues. Note in PR, fix in follow-up.
- **Informational:** style, docs, tooling. Non-blocking.

**Escalate one level** if the contract handles > $1M TVL or is upgradeable.

---

## Common Pitfalls (meta — for the reviewer, not the contract)

1. **Trusting Slither blindly.** Slither misses S04, S17, S21, S22, S23, S28, S29. Run the full manual checklist even when tooling is green.
2. **Reviewing only the diff.** Storage layout, inheritance, and modifiers outside the diff can break a "correct" change. Read the full files.
3. **Ignoring test coverage.** A contract with < 80% branch coverage on state-changing functions is automatically Medium-severity at minimum.
4. **Treating "code looks like OpenZeppelin" as safe.** OpenZeppelin contracts still have version-specific bugs; verify the version and check the changelog.
5. **Forcing every check to apply.** Some contracts genuinely don't have oracles, randomness, or signatures. Mark those **N/A** explicitly — don't fabricate findings.
6. **Missing the meta-pattern.** A single reentrancy guard is not enough if there are 4 entry points. Find the *class* of bugs, not just instances.
7. **Ignoring the upgrade path.** For upgradeable contracts, S26 is not enough — also check initialization (re-initializer) and storage gap consistency.

---

## Verification Checklist

- [ ] Solidity pragma version captured and version-appropriate checks applied
- [ ] Every `.sol` file in scope read in full (not just diff)
- [ ] All 29 checks have an explicit Pass / N/A / Finding verdict
- [ ] Critical and High findings include a PoC sketch (attacker call sequence or failing test)
- [ ] Static analysis tools run where available (Slither / Mythril / forge test) and folded in
- [ ] Report written (or printed) following `reference/report-template.md`
- [ ] Severity escalations noted for upgradeable / high-TVL contracts
- [ ] No silent skips; every "N/A" is justified in one line

---

## Related Skills

- `pr-review-pipeline` — orchestrates this skill as Stage 2 (security lens) of a broader PR review
- `code-reviewer` — general code-quality lens; this skill is the security-first specialist
- `peer-review` — multi-perspective review panel; route Solidity changes here for one perspective
- `frontend-audit` — sibling pattern (exhaustive audit pipeline); borrow the structure if extending this skill
