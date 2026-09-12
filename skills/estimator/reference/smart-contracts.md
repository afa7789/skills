# Smart-contract audit requirements

Load this file only for blockchain/smart-contract projects. Security audits are
mandatory and scale with project size — include the cost in the estimation, flagged
explicitly in the output.

## What triggers an audit

- Any contract handling user funds (DeFi, staking, vaults)
- Token contracts (ERC-20, ERC-721, ERC-1155)
- Governance and voting mechanisms
- Cross-chain bridges or oracle integrations
- Upgradeable proxy patterns

## AI pre-audit cost (grounded in the same turn model as the rest of the skill)

Running AI-assisted analysis before a formal audit reduces audit scope. Budget it in
turns, same cache-aware pricing as everywhere else:

| Activity | Turns | Purpose |
|----------|-------|---------|
| Static analysis passes | 30–120 | Reentrancy, overflow, access control |
| Invariant generation | 20–70 | Property-based test suggestions |
| Gas optimization review | 15–50 | Storage patterns, loop optimization |
| Documentation for auditors | 25–90 | Spec, threat model, architecture docs |

```
pre_audit_turns = 90 – 330      (scale by contract count, not by LOC)
pre_audit_cost  = pre_audit_turns × $0.13
```

Security-critical work sits at the top of the output-per-turn band — expect turns
toward the expensive end (~$0.20 each), so quote $20–$70 for a small protocol and
more for a large one.

**AI pre-audit does not replace a formal audit** — it reduces audit time (and cost)
by catching low-hanging issues first. The formal audit line itself has no cited,
current price table here: quote it from a real auditor, not from this document.

```
Total project cost = Development cost + Pre-audit AI cost + Formal audit cost (real quote)
```
