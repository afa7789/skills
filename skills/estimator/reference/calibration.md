# Calibration provenance

Evidence behind the constants used in `SKILL.md`. Nothing here changes a computed
estimate — the estimate uses only the median/band values already inlined in
`SKILL.md`. Consult this file to justify a number, not to compute one.

**Reproduction tools** (also see AUDIT-016 / SKILL.md §Measure First): `<skill>/scripts/git-hours.py`
reproduces the dev-hours tables below by mining commit timestamps with a session-gap
heuristic; `<skill>/scripts/session-tokens.py --constants` reproduces the token
constants in §Token Estimation. Both are calibration tools, not part of the
per-estimate path — run them only when you have a comparable repo to measure, or
when re-deriving these tables after new data comes in.

## Project Size Reference Table

Sized by turns, priced at the $0.13/turn premium-tier anchor. LOC only locates the
band (proxy) — it is not the driver.

| Project Type | Files | LOC | Turns | Cost (premium, cached) | Audit? |
|-------------|-------|-----|-------|------------------------|--------|
| Script / CLI tool | 3–10 | 500–2k | 20–100 | $3–$13 | — |
| Small web app | 10–20 | 2k–5k | 60–300 | $8–$39 | — |
| Medium MVP (web/desktop) | 20–50 | 5k–15k | 150–700 | $20–$91 | — |
| Large app | 50–100 | 15k–50k | 400–2,000 | $52–$260 | — |
| Complex system (agents) | 100+ | 50k+ | 1,500–6,000 | $195–$780 | — |
| Smart contract (small→protocol) | 5–100+ | 500–30k+ | 50–3,000 | $7–$390 | $5k–$500k+ (real quote) |

## Observed anchors (whole-repo totals, real project histories)

| Shape | Turns | Billed tokens | Cost (premium, cached) |
|-------|-------|---------------|------------------------|
| Multi-phase platform, ~186k net LOC | 830 | 135 M | $106 |
| Full-stack app with polish loops, ~126k net LOC | 1,328 | 177 M | $130 |
| Sustained-burn engine, ~226k net LOC | 2,049 | 578 M | $414 |
| Long-running client monorepo | 5,399 | 1.42 B | $1,036 |

If an estimate lands far outside these anchors, the turn count is wrong — not the
pricing.

## Feature-span observed distribution across the 6 calibration repos

| Repo shape | Span (days) | Features | Same-day % | ≤7d % | ≤30d % | Median span |
|-----------|-------------|----------|------------|-------|--------|-------------|
| Sustained-burn engine | 22 | 38 | 87% | 100% | 100% | 1d |
| Build + tail tool | 39 | 28 | 100% | 100% | 100% | 1d |
| Full-stack app, polish-heavy | 130 | 18 | 12% | 50% | 88% | 8d |
| Frontend app, sprint-and-rest | 117 | 53 | 32% | 49% | 75% | 8d |
| Multi-module monorepo | 114 | 33 | 21% | 48% | 64% | 8d |
| Multi-phase platform | 125 | 17 (cats) | — | — | — | phases 9–41d |

## Dev-hours: measured (n = 6 repos, 945 h, 154 active days)

| Rhythm profile | Commits (top author) | Hours | Active days | c / active day | **h / active day** |
|---------------|---------------------|-------|-------------|----------------|--------------------|
| Sustained burn | 281 | 180.9 | 21 | 13.4 | **7.0** |
| Sprint-and-rest | 241 | 149.0 | 25 | 9.6 | **5.8** |
| Multi-phase platform | 475 | 275.5 | 49 | 9.7 | **5.6** |
| Burst + gap + consolidation | 201 | 125.9 | 23 | 8.7 | **5.4** |
| Polish-loop heavy | 259 | 174.8 | 28 | 9.2 | **5.0** |
| Build + tail | 95 | 39.2 | 8 | 11.9 | **4.9** |

**h/active day is nearly flat: 4.9–7.0, median 5.5 (±19%).** Rhythm profile barely
moves it — what rhythm changes is how many active days fit inside a calendar span,
which the calendar formula already handles. This is why SKILL.md applies the rhythm
multiplier to calendar days only, never to hours.

**Back-test — the formula reproduces the measured hours on all 6 repos (±3%):**

| Rhythm profile | Calendar d | × factor | = active d | × h/day | = predicted h | Measured h | Error |
|---------------|-----------|----------|-----------|---------|---------------|------------|-------|
| Sustained burn | 22 | 0.95 | 20.9 | 7.0 | 146 | 147.5 | −1% |
| Sprint-and-rest | 117 | 0.21 | 24.6 | 5.8 | 143 | 145.0 | −1% |
| Multi-phase platform | 125 | 0.39 | 48.8 | 5.6 | 273 | 275.5 | −1% |
| Burst + gap + consolidation | 114 | 0.20 | 22.8 | 5.4 | 123 | 123.9 | −1% |
| Polish-loop heavy | 130 | 0.22 | 28.6 | 5.0 | 143 | 139.4 | +3% |
| Build + tail | 39 | 0.21 | 8.2 | 4.9 | 40 | 39.2 | +2% |

## Throughput: measured net LOC/hour across the same 6 repos

Lockfiles, `node_modules`, `dist/`, `vendor/`, `.min.`, `.json`, `.snap` excluded.

| Net LOC | Hours | **LOC / h** | Character |
|---------|-------|-------------|-----------|
| 50,181 | 39.2 | **1,280** | Scaffold-heavy burst |
| 224,796 | 180.9 | **1,243** | Codegen + sustained burn |
| 116,241 | 125.9 | **923** | Multi-module monorepo |
| 126,347 | 174.8 | **723** | Full-stack + polish loops |
| 185,164 | 275.5 | **672** | Multi-phase platform |
| 47,124 | 149.0 | **316** | Frontend polish-heavy |

Median 823 LOC/h, band 300–1,300 — SKILL.md's "Project character" table picks a
value from this band by character, not by feature tier.

## Sanity-check anchors (reference projects)

| Your estimate | Compare against |
|---------------|-----------------|
| Small web app (5–10 features) | 53 features / 117 days / 15.6 c/wk (sprint-and-rest) |
| Full-stack MVP (15–20 features) | 18 features / 130 days / 16.2 c/wk (polish-heavy) |
| AI agent pipeline (30+ features) | 38 features / 22 days (sustained burn) |
| Multi-module platform (15+ cats) | phases of 9–41 days each (multi-phase) |

If your estimate diverges >2x from these anchors, re-check: are you double-counting
polish loops, did you apply the rhythm multiplier, are burst days hiding working-day
effort.

## Why these constants are shaped this way (literature)

| Finding | Source | Consequence for this skill |
|---------|--------|----------------------------|
| Session-gap heuristic is the standard way to get hours out of git: a gap ≤ *G* continues a session, a larger gap opens a new one, and each session is credited *F* extra minutes for work before its first commit. Defaults `G = F = 120 min`. | [git-hours](https://github.com/kimmobrunfeldt/git-hours), [git-estimate](https://github.com/luigitni/git-estimate), [commit-cadence analysis](https://betterprogramming.pub/measuring-the-cadence-of-commits-in-git-history-ed58590a3b0e) | `git-hours.py` implements it — run it on any repo you have instead of guessing hours/day. |
| Git metrics approximate effort at best ~61% correlation — never a substitute for measurement. | [GitClear productivity guide](https://www.gitclear.com/measuring_developer_productivity_a_comprehensive_guide_for_the_data_driven), [Contribution Rate Imputation Theory](https://arxiv.org/pdf/2410.09285) | Quote a band, never a point number; never sell derived hours as measured. |
| Self-reported AI speedup is systematically wrong — experienced devs were 19% slower with AI in an RCT while believing they were 20% faster. | [METR, Jul 2025](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/), [summary](https://www.seangoedecke.com/impact-of-ai-study/) | The AI-assistance factor table in SKILL.md sets mature ≥100k-LOC repos to **1.19x** (a slowdown), not a discount. |
