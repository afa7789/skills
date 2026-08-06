# Solidity Review Report — Template

Use this template for `SOLIDITY_REVIEW.md`. Replace every `{{placeholder}}`.

---

```markdown
# Solidity Review — {{contract_or_pr_name}}

**Date:** {{ISO date}}
**Reviewer:** {{agent / human}}
**Scope:** {{files or PR diff}}
**Solidity version:** {{pragma}}
**Verdict:** {{PASS | PASS WITH NITS | CHANGES REQUESTED | BLOCKED}}

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | {{n}} |
| High     | {{n}} |
| Medium   | {{n}} |
| Low      | {{n}} |
| Info     | {{n}} |

**Headline finding:** {{one sentence — usually the worst single issue, or "No critical or high issues."}}

---

## Findings

### {{SEVERITY}} — {{S##: short title}}

**Location:** `{{file}}:{{line range}}`
**Pattern observed:**
```solidity
{{paste the vulnerable code snippet, 3-10 lines}}
```

**Impact:** {{1-3 sentences. Who loses what under what condition.}}

**Recommendation:**
```solidity
{{paste the fixed code snippet}}
```

**PoC sketch:**
```
{{attacker call sequence, or a forge/hardhat test case that reproduces}}
```

**Reference:** See `reference/checklist.md` § S{{##}}.

---

(repeat the block above for each finding)

---

## 29-Check Verdict Table

| ID | Check | Verdict | Severity if found |
|----|-------|---------|-------------------|
| S01 | Division before multiplication | Pass / N/A / **Finding** | — |
| S02 | Check-Effects-Interaction | Pass / N/A / **Finding** | — |
| ... | ... | ... | ... |
| S30 | Unprotected `selfdestruct` | Pass / N/A / **Finding** | — |
| S31 | Default function visibility | Pass / N/A / **Finding** | — |
| S32 | Off-by-one / loop bounds | Pass / N/A / **Finding** | — |
| S33 | Centralization / missing pause | Pass / N/A / **Finding** | — |
| S34 | Precision loss in fixed-point math | Pass / N/A / **Finding** | — |
| S35 | Variable shadowing | Pass / N/A / **Finding** | — |

---

## Tooling Results

- **Slither:** {{ran? output summary — link to full log if relevant}}
- **Mythril:** {{ran? output summary}}
- **forge test / forge coverage:** {{ran? pass? coverage %}}

> Note: Slither does not detect S04, S17, S21, S22, S23, S28, S29. Manual review covered those.

---

## N/A Justifications

(List every check marked N/A with one line of reason. e.g. "S21 N/A — contract has no price oracle; uses only fixed-ratio math.")

---

## Follow-ups (non-blocking)

- {{item}}
- {{item}}
```
