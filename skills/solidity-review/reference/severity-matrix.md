# Severity Matrix

Use this matrix to translate findings into consistent severity grades. Default severity per check is in `SKILL.md`; override based on context (TVL, upgradeability, admin trust model).

---

## Severity Definitions

| Severity | Definition | Merge gate |
|----------|------------|------------|
| **Critical** | Direct loss of user funds, full protocol compromise, or unstoppable drain under any realistic condition. | **Block merge.** Fix or formally accept risk with sign-off. |
| **High** | Exploitable under realistic but not always-on conditions; significant fund loss or invariant break. | **Block merge.** Fix before merge. |
| **Medium** | Exploitable only with specific conditions (admin key compromise, particular state, specific timing); OR significant DoS / logic bug; OR test coverage < 80% on critical paths. | **Should fix before merge.** Can be deferred only with team sign-off and an issue. |
| **Low** | Code-quality, gas, or best-practice issue. No direct exploit. | **Note in PR.** Fix in follow-up. |
| **Informational** | Style, docs, formatting. Non-blocking. | **Note only.** |

---

## Escalation Rules

Escalate one level (Critical → Critical stays, High → Critical, Medium → High, etc.) when **any** of:

- The contract handles > $1M TVL.
- The contract is upgradeable (proxy pattern).
- The contract is a core dependency used by 3+ other contracts.
- The vulnerability affects an admin function with a single-key owner.
- The contract has been deployed and there is no pause/upgrade path.

De-escalate one level only when **all** of:

- The contract handles < $50k and is fully immutable.
- The finding requires an admin key compromise AND the admin is a multisig.
- The vulnerable code path is gated by a feature flag that's off in production.

---

## Severity → Action Mapping

| Severity | Required action |
|----------|-----------------|
| Critical | Fix in this PR. Add a regression test. Optionally: a PoC in the PR description. |
| High | Fix in this PR. Add a regression test. |
| Medium | Fix in this PR or open a tracked issue. Tests optional but encouraged. |
| Low | Tracked follow-up issue is fine. |
| Info | Optional follow-up. |

---

## Common Mis-Grading Pitfalls

1. **Treating "no impact today" as Low.** Reentrancy in a non-payable function is still High if the function later becomes payable.
2. **Treating oracle issues as Low because the current price looks fine.** S21 / S22 are Critical whenever they apply.
3. **Marking gas issues as Info.** Unbounded loops that will DoS the contract are High (S08 / S24).
4. **Marking access control as Medium.** Public `setOwner` or `setPrice` with no auth is High (S07).
5. **Treating "uses OpenZeppelin" as automatically safe.** OZ version bugs are real. S05 still applies to OZ consumers if they bypass `safeTransfer`.
6. **Marking missing events as Info.** If off-chain systems depend on the events (subgraphs, governance, accounting), missing events are Medium.
