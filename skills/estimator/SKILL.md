---
name: estimator
description: Multi-step project estimation with intermediate result saving. Estimates tokens, USD cost, dev-hours, AND wall-clock calendar time calibrated against measured git history (n=6 repos, 945 h) and measured Claude Code session usage (n=15 projects, 3.2B tokens). Saves paths.md, plan.md, steps.md, and estimative.md.
---

You are a project estimation specialist that estimates token costs and project scope from ideas/prompts.

## Prerequisites

**RTK (Rust Token Killer) must be initialized in the target project:**

```bash
# In the project directory you will work on:
rtk init
```

This enables token-optimized command output for analysis.

## Output Files

All results are saved to files with the given slug:

- `{slug}-paths.md` — File paths and metadata from analysis
- `{slug}-plan.md` — The analysis plan and approach
- `{slug}-steps.md` — Step-by-step progress log
- `{slug}-estimative.md` — Final estimation results

A re-run **overwrites** all four. The previous generation is rotated to `{slug}-*.prev.md`
(one level only) so the new estimate can be diffed against it — see Step 0.

---

## Token Estimation — Turn-Based (MEASURED)

> **Never estimate tokens from LOC.** Measurement over 15 real Claude Code project
> histories (16k+ assistant turns, 3.2 B billed tokens, `scripts/session-tokens.py`)
> shows the old `code_tokens × 10` rule under-counts by one to two orders of magnitude.
> What gets billed is **conversation context re-sent on every turn**, not the code that
> survives at the end. A 200-line file discussed across 40 turns is billed ~40 times.

Reproduce every number below with:

```bash
python3 scripts/session-tokens.py --constants
```

### The unit of cost is one assistant turn

**Tight constants (spread < 7× — safe as anchors):**

| Per assistant turn | min | **median** | max | spread |
|--------------------|-----|------------|-----|--------|
| Total billed tokens | 44 k | **135 k** | 282 k | 6.4× |
| Output tokens | 290 | **1,000** | 1,840 | 6.3× |
| USD, premium tier, cache-aware | $0.04 | **$0.13** | $0.20 | 5.3× |
| Cache-read share of input | 84 % | **97 %** | 98 % | — |

**Loose constants (spread > 20× — order of magnitude only, never a point estimate):**

| Ratio | min | median | max | spread |
|-------|-----|--------|-----|--------|
| Net LOC / dev-hour | 316 | 823 | 1,288 | 4× |
| Turns / dev-hour | 4 | 26 | 88 | 20× |
| Added LOC / turn | 9 | 22 | 178 | 20× |
| Tokens / added LOC | 585 | 7.7 k | 24 k | **42×** |
| Tokens / dev-hour | 0.4 M | 3.5 M | 14 M | 35× |
| USD / dev-hour | $0.28 | $3.30 | $10.47 | 37× |

> **Why turns/hour and tokens/hour are useless as anchors:** heavy sub-agent and
> background usage decouples turn count from human-attended hours. One dev-hour can
> carry 4 turns or 88. Estimate turns **per deliverable**, never per hour.

### Cache pricing is not optional

97 % of billed input is a **cache read**, priced at 0.10× base input. Ignoring the cache
over-prices the input leg by roughly 10×. Split every input estimate:

```
input_tokens       = turns × 134,000
cache_read_tokens  = input_tokens × 0.97   →  price × 0.10
cache_write_tokens = input_tokens × 0.03   →  price × 1.25
output_tokens      = turns × 1,000         →  price × 1.00
```

Extended-thinking tokens are billed **as output** — do not add a separate reasoning leg,
and do not price it differently. Raise `output_tokens / turn` toward the 1,840 ceiling for
reasoning-heavy work instead.

### Step 1 — Estimate turns per deliverable

Turns are the thing you estimate. Derive them from the deliverable list, then cross-check
against the added-LOC/turn band (median 22, band 9–178):

| Feature tier | Typical net LOC | Turns (median rate) | Turns (band) |
|--------------|-----------------|---------------------|--------------|
| trivial (rename, 1-line fix) | ~30 | 2 | 1–4 |
| simple (isolated util, config) | ~465 | 21 | 3–50 |
| medium (single module, CRUD, fix-loop) | ~1,500 | 68 | 8–170 |
| complex (multi-module, design decisions) | ~5,000 | 227 | 30–560 |
| critical (architecture, RAG, full-stack) | ~12,000 | 545 | 70–1,300 |

Add non-feature turns explicitly — they are real and often 20–30 % of the total:

| Activity | Turns |
|----------|-------|
| Planning, architecture, spec | 20–80 |
| Test authoring and green-loop | 30 % of feature turns |
| Debug / build-fix cycles | 25 % of feature turns |
| Review, refactor, polish loops | 15 % of feature turns |
| Documentation, CI/CD, deploy | 15–60 |

### Step 2 — Price it

Run `python3 scripts/estimate-cost.py --turns N ...` for the arithmetic; the formula below is the spec it implements.

```
turns   = Σ feature_turns + planning + tests + debug + review + docs
tokens  = turns × 135,000                                    # band 44k–282k
cost    = turns × $0.13                                      # band $0.04–$0.20
```

Always quote the band, never the point. `turns × $0.13` and the explicit cache split must
agree — if they diverge, the cache-read share is wrong.

### Sanity gates

| Gate | Expected | If violated |
|------|----------|-------------|
| USD per turn | $0.04 – $0.20 | Pricing or cache split is wrong |
| Tokens per turn | 44 k – 282 k | Context-size assumption is wrong |
| Tokens per added LOC | 600 – 25 k | Turn count or LOC estimate is wrong |
| Output share of tokens | 0.4 % – 2 % | Output legs double-counted |

### LOC → tokens (sanity check ONLY)

This table converts source lines into *code* tokens. It answers "how big is one file in
context", **not** "what will this project cost". Never multiply it to reach a project total.

| Language / Type | Tokens/Line | Dense* | Chars/Token |
|-----------------|-------------|--------|-------------|
| Python | ~10 | ~12 | ~4.2 |
| JavaScript | ~7–8 | ~10 | ~4.0 |
| TypeScript (typed) | ~9–10 | ~13 | ~3.8 |
| Svelte 5 (runes + TS) | ~10–12 | ~14 | ~3.8 |
| Rust (simple) | ~10–12 | ~14 | ~3.8 |
| Rust (macros/generics/lifetimes) | ~14–16 | ~18 | ~3.5 |
| Solidity / Smart Contracts | ~12–14 | ~16 | ~3.6 |
| Java / C# / Go | ~9–11 | ~13 | ~3.8–4.2 |
| SQL / Config files | ~11–12 | ~12 | ~3.5 |
| MASM / Assembly | ~8–10 | ~12 | ~4.0 |
| Mixed codebase (avg) | **~10** | ~14 | ~3.8 |

\* *Dense = macros, generics, complex types, derive attributes, interface types, runes*

Each file loaded into context also costs ~150 tokens of path/separator metadata.

### Complexity: raise turns, not multipliers

Complexity does not get its own multiplier. It moves the **turn count** and the
**output-per-turn** figure, both of which are already in the model:

| Complexity | Turn adjustment | Output/turn | Examples |
|------------|-----------------|-------------|----------|
| Simple | ×1.0 | ~600 | CRUD, config, known patterns |
| Medium | ×1.3 | ~1,000 | Design decisions, some research |
| Complex | ×1.8 | ~1,400 | Novel architecture, Rust lifetimes, crypto |
| Critical (auditable) | ×2.5 | ~1,800 | Smart contracts, financial, security-sensitive |

---

## Model Pricing (USD per 1M tokens)

### Claude (Anthropic)

Cache write is 1.25× input; cache read is 0.10× input. Extended thinking bills as output.

| Model | Input | Cache write | Cache read | Output | Context |
|-------|-------|-------------|------------|--------|---------|
| Opus 5 / Opus 4.6 | $5.00 | $6.25 | $0.50 | $25.00 | 200k (1M variant) |
| Fable 5 | $10.00 | $12.50 | $1.00 | $50.00 | 1M |
| Sonnet 5 | $2.00 | $2.50 | $0.20 | $10.00 | 200k |
| Sonnet 4.6 | $3.00 | $3.75 | $0.30 | $15.00 | 200k |
| Haiku 4.5 | $1.00 | $1.25 | $0.10 | $5.00 | 200k |

> **Effective blended rate at the measured 97 % cache-read share:** a premium-tier turn
> costs ~$0.13, not the ~$0.70 a naive full-price input calculation produces. Providers
> without prompt caching lose this discount entirely — price them at full input rate.

### Top Market Models (Calibrated 2026-08-27)

> **Source:** llmgateway.io aggregator (GitHub: `theopenco/llmgateway`) — aggregates official prices from 40+ providers. Prices verified via raw GitHub source `packages/models/src/models/*.ts`. Updated monthly by community; pull before estimating.

**Tier 1 — Premium (quality matters most)**

| Model | Input | Output | Context | Notes |
|-------|-------|--------|---------|-------|
| Claude Opus 4.6 | $5.00 | $25.00 | 200k | Opus-tier pricing, identical across Opus 4.5–5 |
| Claude Opus 5 | $5.00 | $25.00 | 200k | Opus-tier pricing (Anthropic price-stable) |
| Claude Fable 5 | $10.00 | $50.00 | 1M | Top tier — 2x Opus price, 5x context |
| Gemini 3 Pro Preview | $2.00 | $12.00 | 1M | Google flagship, 1M context |

**Tier 2 — Balanced (default for most projects)**

| Model | Input | Output | Context | Notes |
|-------|-------|--------|---------|-------|
| Claude Sonnet 4.6 | $3.00 | $15.00 | 200k | Stable mid-premium |
| Claude Sonnet 5 | $2.00 | $10.00 | 200k | 33% cheaper than Sonnet 4.6 |
| Grok 4 (reasoning) | $3.00 | $15.00 | 256k | xAI flagship |
| Gemini 2.5 Pro | $1.25 | $10.00 | 1M | Best value premium |
| Mistral Large 3 | $0.50 | $1.50 | 128k | 10x cheaper than Sonnet 4.6 |
| DeepSeek V3.2 | $0.28 | $0.42 | 164k | Cheapest "good" output |

**Tier 3 — Budget (mechanical work, CRUD, migrations)**

| Model | Input | Output | Context | Notes |
|-------|-------|--------|---------|-------|
| Gemini 2.5 Flash Lite | $0.10 | $0.40 | 1M | Ultra-budget, 1M context |
| Grok 4.1 Fast | $0.20 | $0.50 | 2M | Largest context window (2M) |
| MiniMax M2.5 | $0.30 | $1.20 | 197k | Cheap input ($0.19 quoted externally, $0.30 on llmgateway) |
| MiniMax M2.7 | $0.30 | $1.20 | 205k | Latest MiniMax budget |
| DeepSeek V4 Flash | $0.14 | $0.28 | 128k | Cheaper than V3.2 |
| Qwen Turbo | $0.05 | $0.20 | 1M | Alibaba ultra-budget |
| GLM-4.5 Air | $0.20 | $1.10 | 131k | Z.ai budget tier |
| Llama 4 Scout | $0.18 | $0.59 | 10M | Meta open-weights |
| Mistral Small 3.2 | $0.10 | $0.30 | 128k | Cheapest Mistral |

**External (not on llmgateway aggregator — quote official source):**

| Model | Input | Output | Source |
|-------|-------|--------|--------|
| Xiaomi MiMo-V2-Pro | $1.00 | $3.00 | xiaomi directly |
| StepFun Step 3.5 Flash | $0.00 | $0.00 | stepfun directly |

### Quick Cost Comparison (per 1M tokens, weighted at the measured 99/1 input/output split)

> The measured output share is **~1 % of billed tokens**, not 25 %. Input price dominates
> almost entirely — which is exactly why prompt caching decides the bill.

| Tier | Models | Combined $/1M (weighted) |
|------|--------|--------------------------|
| **Free** | Qwen Turbo (free tier), StepFun 3.5 Flash | $0–$0.06 |
| **Ultra-budget** | Gemini 2.5 Flash Lite, Mistral Small 3.2, DeepSeek V4 Flash, Grok 4.1 Fast | $0.10–$0.21 |
| **Budget** | Mistral Large 3, MiniMax M2.5/M2.7, Gemini 3 Pro, GLM-4.5 Air | $0.30–$2.10 |
| **Mid-range** | Claude Sonnet 5, Sonnet 4.6, GLM-5, Grok 4 | $2.08–$3.12 |
| **Premium** | Claude Opus 4.6/5, Claude Fable 5 | $5.20–$10.40 |

**With Anthropic prompt caching at the measured 97 % cache-read share**, the effective
Claude rates drop to roughly: Opus/Fable **$0.96 / $1.92** per 1M, Sonnet 5 **$0.39**,
Haiku 4.5 **$0.19**. Always state whether a quote is cached or uncached.

### Cost Calculation Formula

Cache-aware, the only correct form:

Run `python3 scripts/estimate-cost.py --turns N ...` for the arithmetic; the formula below is the spec it implements.

```
input_tokens = turns × 134,000
cost = ( input_tokens × 0.97 × cache_read_price
       + input_tokens × 0.03 × cache_write_price
       + turns × 1,000      × output_price ) / 1,000,000
```

Cross-check against the direct anchor: `cost ≈ turns × $0.13` on premium tier. The two must
land within ~20 % of each other.

For providers **without** prompt caching, drop the split and use full input price on every
token — the same workload costs roughly 8–10× more.

### Model Selection Guide

| Project Type | Recommended (2026-08) | Why |
|-------------|------------------------|-----|
| Quick prototype / script | Mistral Small 3.2, Gemini 2.5 Flash Lite | $0.10-0.30/M, good enough for simple code |
| Medium MVP | Current Sonnet-tier Claude | Default mid-premium tier |
| Complex system (Rust, crypto, agents) | Current Opus-tier Claude | Best reasoning without the top-tier price jump |
| Budget-constrained, high volume | Grok 4.1 Fast, DeepSeek V4 Flash | 2M context + sub-$0.50/M |
| Reasoning-heavy / math | Grok 4, Gemini 2.5 Pro | Strong at structured output |
| Long-context (RAG, big codebases) | Llama 4 Scout (10M), Gemini 2.5 Flash Lite (1M) | Largest contexts available |
| Exploration / brainstorming | StepFun 3.5 Flash | Free, good for drafting |

---

## Smart Contract Audit Requirements

For **blockchain/smart contract** projects, security audits are mandatory and scale with project size. Include these costs in the estimation.

### Audit Tiers by Project Size

| Project Size | LOC (Solidity/Rust) | Audit Tier | Estimated Audit Cost | Timeline |
|-------------|---------------------|------------|---------------------|----------|
| Micro (single contract) | <500 | Automated only | $500–$2k | 1-3 days |
| Small (2-5 contracts) | 500–2k | Automated + 1 auditor | $5k–$15k | 1-2 weeks |
| Medium (DeFi protocol) | 2k–10k | Full audit (2-3 auditors) | $30k–$80k | 3-6 weeks |
| Large (complex protocol) | 10k–30k | Multiple audits recommended | $80k–$200k | 6-12 weeks |
| Critical (L1/L2/bridge) | 30k+ | Multiple firms + formal verification | $200k–$500k+ | 3-6 months |

### What Triggers an Audit

- Any contract handling user funds (DeFi, staking, vaults)
- Token contracts (ERC-20, ERC-721, ERC-1155)
- Governance and voting mechanisms
- Cross-chain bridges or oracle integrations
- Upgradeable proxy patterns

### Audit Token Cost (AI-Assisted Pre-Audit)

Running AI-assisted analysis before a formal audit reduces audit scope. Budget it in turns:

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

Security-critical work sits at the top of the output-per-turn band — expect turns toward the
expensive end (~$0.20 each), so quote `$20–$70` for a small protocol and more for a large one.

> **Important:** AI pre-audit does NOT replace a formal audit. It reduces audit time (and
> cost) by catching low-hanging issues first.

### Including Audit in Total Estimation

```
Total project cost = Development cost + Pre-audit AI cost + Formal audit cost
```

Always flag smart contract projects in the estimation output with audit requirements.

---

## Project Size Reference Table

Sized by **turns**, priced at the measured $0.13/turn premium-tier anchor. LOC is shown only
to locate the band — it is not the driver. Turn ranges use the added-LOC/turn band (9–178),
so they are deliberately wide; narrow them with a deliverable decomposition, not by picking
the midpoint.

| Project Type | Files | LOC | Turns | Tokens | Cost (premium, cached) | Audit? |
|-------------|-------|-----|-------|--------|------------------------|--------|
| Script / CLI tool | 3–10 | 500–2k | 20–100 | 3M–14M | $3–$13 | — |
| Small web app | 10–20 | 2k–5k | 60–300 | 8M–40M | $8–$39 | — |
| Medium MVP (web/desktop) | 20–50 | 5k–15k | 150–700 | 20M–95M | $20–$91 | — |
| Large app | 50–100 | 15k–50k | 400–2,000 | 54M–270M | $52–$260 | — |
| Complex system (agents) | 100+ | 50k+ | 1,500–6,000 | 200M–810M | $195–$780 | — |
| Smart contract (small) | 5–15 | 500–2k | 50–250 | 7M–34M | $7–$33 | $5k–$15k |
| Smart contract (DeFi) | 15–40 | 2k–10k | 200–900 | 27M–120M | $26–$117 | $30k–$80k |
| Smart contract (protocol) | 40–100+ | 10k–30k+ | 700–3,000 | 95M–405M | $91–$390 | $80k–$500k+ |

**Observed anchors** (real project histories, whole-repo totals):

| Shape | Turns | Billed tokens | Cost (premium, cached) |
|-------|-------|---------------|------------------------|
| Multi-phase platform, ~186k net LOC | 830 | 135 M | $106 |
| Full-stack app with polish loops, ~126k net LOC | 1,328 | 177 M | $130 |
| Sustained-burn engine, ~226k net LOC | 2,049 | 578 M | $414 |
| Long-running client monorepo | 5,399 | 1.42 B | $1,036 |

If an estimate lands far outside these anchors, the turn count is wrong — not the pricing.

---

## Workflow

### Step 0 — Get the slug and reset previous output

Ask the user for a project slug (e.g., "my-api-project", "react-dashboard").

**A re-run overwrites the previous estimate — it never appends.** Before writing anything:

```bash
for f in {slug}-paths.md {slug}-plan.md {slug}-steps.md {slug}-estimative.md; do
  [ -f "$f" ] && mv -f "$f" "${f%.md}.prev.md"
done
```

This keeps exactly one previous generation as `{slug}-*.prev.md` so the new estimate can be
diffed against it, and guarantees stale sections from an older run never leak into the new
one. If `{slug}-estimative.prev.md` exists, add a **Revision History** row to the new
estimative recording what changed and why.

Initialize `{slug}-steps.md`:
````markdown
# Steps: {slug}

## Step 1: Analyze Prompt
- Status: pending|done
- Notes:

## Step 2: Heavy Thinker (Research & Spec)
- Status: pending|done
- Notes:

## Step 3: Identify Files
- Status: pending|done
- Notes:

## Step 4: Estimate Deliverables & LOC
- Status: pending|done
- Notes: LOC is a sanity check, not the driver.

## Step 5: Count Turns & Price
- Status: pending|done
- Notes: Turns per deliverable + non-feature turns; price cache-aware; run the sanity gates.

## Step 6: Final Estimation
- Status: pending|done
- Notes:

## Step 7: Wall-Clock Calibration (Time Estimation)
- Status: pending|done
- Notes: For each unit-feature, classify complexity (trivial/simple/medium/complex/critical) and apply the span table. Compute rhythm multiplier (sustained/sprint-and-rest/build+tail/burst+gap/polish-heavy). Count polish-loop rate. Output calendar days + working days + dev-hours (cadence vs throughput, reconciled).
````

---

### Step 1 — Analyze Prompt

Understand the user's idea/prompt:
1. What is the goal?
2. What type of project? (API, webapp, CLI, library, etc.)
3. What technologies/languages?
4. What features?
5. What complexity level? (simple/medium/complex)

Save analysis to `{slug}-plan.md`:
````markdown
# Plan: {slug}

## Prompt Analysis
- Goal:
- Project Type:
- Technologies:
- Languages:
- Features:
- Complexity: simple|medium|complex

## Heavy Thinker: Research & Spec

### Research Topics
- Topic 1: [searches needed, estimated tokens]
- Topic 2: [searches needed, estimated tokens]

### Architecture Decisions
- Decision 1: [trade-offs, implications]
- Decision 2: [trade-offs, implications]

### Spec Requirements
- API spec: {turns}
- Data models: {turns}
- README: {turns}

### Research Turn Estimate
- Web searches: ~{n} queries → ~{n} turns
- Docs reading: ~{n} docs → ~{n} turns
- Code analysis: ~{n} files → ~{n} turns
- **Subtotal Research**: ~{n} turns (~{n × 135k} tokens, ~${n × 0.13})
````

Update `{slug}-steps.md`.

---

### Step 6 — Final Estimation

Create `{slug}-estimative.md`:
````markdown
# Estimation: {slug}

## Project Summary
- Goal: {description}
- Type: {project-type}
- Languages: {list with tokens/line rates}
- Complexity: simple|medium|complex

## File Structure
- Total files: {n}
- Total lines: {n}
- Technologies: {list}

## Deliverable Breakdown

| Deliverable | Tier | Net LOC (est) | Turns | Confidence |
|-------------|------|---------------|-------|------------|
| {feature 1} | medium | 1,500 | 68 | med |
| {feature 2} | complex | 5,000 | 227 | low |
| **Feature subtotal** | — | {n} | **{n}** | — |

### Non-Feature Turns

| Activity | Rule | Turns |
|----------|------|-------|
| Planning / architecture / spec | 20–80 | {n} |
| Tests | 30 % of feature turns | {n} |
| Debug / build-fix loops | 25 % of feature turns | {n} |
| Review / refactor / polish | 15 % of feature turns | {n} |
| Docs / CI-CD / deploy | 15–60 | {n} |
| **Non-feature subtotal** | — | **{n}** | 

- **Total turns:** {low} / **{base}** / {high}
- Complexity turn adjustment applied: ×{1.0–2.5} ({tier})

## Token Estimate

| Leg | Formula | Tokens | Price/1M | Cost |
|-----|---------|--------|----------|------|
| Cache read | turns × 135k × 0.97 | {n} | $0.50 | ${x} |
| Cache write | turns × 135k × 0.03 | {n} | $6.25 | ${x} |
| Output | turns × 1,000 | {n} | $25.00 | ${x} |
| **Total** | — | **{n}** | — | **${x}** |

- **Direct anchor cross-check:** {turns} × $0.13 = ${x} — within 20 % of the table: yes|no
- **Scenario band:** ${low} (44k tok/turn) / **${base}** (135k) / ${high} (282k tok/turn)

### Sanity Gates

| Gate | Expected | Computed | Pass |
|------|----------|----------|------|
| USD / turn | $0.04–$0.20 | ${x} | ✅/❌ |
| Tokens / turn | 44k–282k | {n} | ✅/❌ |
| Tokens / added LOC | 600–25k | {n} | ✅/❌ |
| Output share | 0.4 %–2 % | {x} % | ✅/❌ |

*Any ❌ means the turn count or context assumption is wrong — fix it, do not fudge the price.*

## Cost by Model (same turn count)

| Model | Cache read | Cache write | Output | **Total** |
|-------|-----------|-------------|--------|-----------|
| Opus 5 | ${x} | ${x} | ${x} | **${x}** |
| Sonnet 5 | ${x} | ${x} | ${x} | **${x}** |
| Haiku 4.5 | ${x} | ${x} | ${x} | **${x}** |
| No-cache provider (full input price) | — | — | — | **${x}** |

**Recommended model for this project:** {model} — {reason}
**Budget alternative:** {model} — {reason}

## Smart Contract Audit (if applicable)

| Item | Estimated Cost | Notes |
|------|---------------|-------|
| AI pre-audit | {n} turns (~${x}) | Static analysis, invariants, gas review |
| Formal audit (external) | ${x} | Based on {LOC} LOC, {tier} tier — indicative, requires a real quote |
| **Total with audit** | **${dev + audit}** | Development + audit combined |

*Omit this section for non-smart-contract projects.*
````

## Time & Wall-Clock Estimation (Calibrated)

> **Calibration source:** 6 real repositories mined by git history — 1 developer, 945 measured
> hours, 154 active days, 132 unit-features aggregated. Repos are not named; only the derived
> ratios matter. Reproduce any of them on your own repo with `scripts/git-hours.py`.

### Feature-Span Calibration (Calendar Days, First→Last Commit)

> Each row is the observed median across unit-features in the calibration set.
> **Sustained-burn projects** show low per-feature spans because all features ship within 1–3
> active days — total calendar duration is the SUM of feature spans, not any single span.

| Complexity | Median span | Mean span | p90 span | LOC median | n (features) |
|------------|-------------|-----------|----------|-----------|--------------|
| **trivial** (rename, typo, 1-line) | 1d | 0.3d | 1d | ~0 | 2+ |
| **simple** (small util, isolated config) | 1d | 0.5d | 2d | 465 | 9 |
| **medium** (single module, CRUD, fix-loop) | 2d | 3d | 8d | 1,500 | 28 |
| **complex** (multi-module, design decisions) | 8d | 12d | 28d | 5,000 | 15+ |
| **critical** (architecture, multi-agent, RAG, full-stack) | 28d | 30d | 60d+ | 12,000+ | 5+ |

**Observed distribution across the 6 repos (anonymized):**

| Repo shape | Span (days) | Features | Same-day % | ≤7d % | ≤30d % | Median span |
|-----------|-------------|----------|------------|-------|--------|-------------|
| Sustained-burn engine | 22 | 38 | 87% | 100% | 100% | 1d |
| Build + tail tool | 39 | 28 | 100% | 100% | 100% | 1d |
| Full-stack app, polish-heavy | 130 | 18 | 12% | 50% | 88% | 8d |
| Frontend app, sprint-and-rest | 117 | 53 | 32% | 49% | 75% | 8d |
| Multi-module monorepo | 114 | 33 | 21% | 48% | 64% | 8d |
| Multi-phase platform | 125 | 17 (cats) | — | — | — | phases 9–41d |

### Rhythm Profiles (Real Patterns)

Projects don't burn linearly. Identify the profile to avoid under-estimation:

| Profile | Trigger | Wall-clock multiplier |
|---------|---------|----------------------|
| **Sustained burn** | Daily commits, even spread | 1.0x |
| **Sprint-and-rest** | Bursts of 3–7d, then gap | 1.4x |
| **Build + tail** | Heavy phase + 1–2 commits/month | 1.6x |
| **Burst + gap + consolidation** | 2 phases with month-long gap | 1.8x |
| **Polish-loop heavy** | >10% commits are sub-200-LOC fix/chore | 1.5x |

### Polish-Loop Detection

Count polish-loop commits BEFORE estimating. A polish-loop = a sub-200-LOC commit dominated by:
- `fix:` (typo, null-check, optional-chain, banner spacing)
- `style:` / `chore:` (rename, reformat)
- `docs:` (typo, link)
- `refactor:` (no behavior change, no new tests)

| Polish-loop rate | Implication | Add to estimate |
|------------------|-------------|-----------------|
| <5% of commits | Healthy | 0 |
| 5–10% | Normal iterative | +20% |
| 10–20% | Polish-heavy | +50% |
| >20% | Review-fix loop not converging | +100% (and reconsider scope) |

### Working-Day Conversion

Calendar days ≠ working days. Active days counted as distinct commit-days (`scripts/git-hours.py`):

| Rhythm | Active / calendar days | Active days per week | `working_day_factor` |
|--------|------------------------|----------------------|----------------------|
| Sustained burn | 0.95 | 6.7 | **0.95** |
| Multi-phase platform | 0.39 | 2.7 | **0.39** |
| Polish-loop heavy | 0.22 | 1.5 | **0.22** |
| Sprint-and-rest | 0.21 | 1.5 | **0.21** |
| Build + tail | 0.21 | 1.4 | **0.21** |
| Burst + gap + consolidation | 0.20 | 1.4 | **0.20** |

> Everything except sustained burn lands at **~0.20–0.22** — roughly *1.5 active days per
> calendar week*. That is the honest solo-side-project rate.

> **Rule of thumb:** solo AI-assisted dev moves ~500–2,000 net LOC per **active day** at the
> "medium" tier; scaffold- and codegen-heavy projects reach ~16k/day.

### Dev-Hours Calibration (MEASURED)

> **Provenance:** hours below were **measured**, not guessed — `scripts/git-hours.py` ran the
> session-gap algorithm (`--max-gap 120 --first-commit 120`) over 6 repos. Reproduce with:
> `python3 scripts/git-hours.py --repo /path/to/repo`
> They are still *inferred from commit timestamps*, not timesheets — quote a band, never a point.

**Measured hours per active day (n = 6 repos, 945 h, 154 active days):**

| Rhythm profile | Commits (top author) | Hours | Active days | c / active day | **h / active day** |
|---------------|---------------------|-------|-------------|----------------|--------------------|
| Sustained burn | 281 | 180.9 | 21 | 13.4 | **7.0** |
| Sprint-and-rest | 241 | 149.0 | 25 | 9.6 | **5.8** |
| Multi-phase platform | 475 | 275.5 | 49 | 9.7 | **5.6** |
| Burst + gap + consolidation | 201 | 125.9 | 23 | 8.7 | **5.4** |
| Polish-loop heavy | 259 | 174.8 | 28 | 9.2 | **5.0** |
| Build + tail | 95 | 39.2 | 8 | 11.9 | **4.9** |

> ### 🔑 The finding that matters
> **h/active day is nearly flat: 4.9–7.0, median 5.5 (±19%).** Rhythm profile barely moves it.
> What rhythm actually changes is *how many active days exist inside a calendar span* — which
> the calendar formula already handles.
>
> **Consequence: apply the rhythm multiplier to calendar days ONLY. Never to hours.**
> Doing both double-counts.

| Use case | h/active day |
|----------|--------------|
| Default (any profile, no better data) | **5.5** |
| Sustained burn / full-time focus | 7.0 |
| Part-time, tail phase, or maintenance | 4.9 |
| Band to quote | **5.0–7.0** |

**Back-test — the formula reproduces the measured hours on all 6 repos:**

| Rhythm profile | Calendar d | × factor | = active d | × h/day | = predicted h | Measured h | Error |
|---------------|-----------|----------|-----------|---------|---------------|------------|-------|
| Sustained burn | 22 | 0.95 | 20.9 | 7.0 | 146 | 147.5 | −1% |
| Sprint-and-rest | 117 | 0.21 | 24.6 | 5.8 | 143 | 145.0 | −1% |
| Multi-phase platform | 125 | 0.39 | 48.8 | 5.6 | 273 | 275.5 | −1% |
| Burst + gap + consolidation | 114 | 0.20 | 22.8 | 5.4 | 123 | 123.9 | −1% |
| Polish-loop heavy | 130 | 0.22 | 28.6 | 5.0 | 143 | 139.4 | +3% |
| Build + tail | 39 | 0.21 | 8.2 | 4.9 | 40 | 39.2 | +2% |

Within ±3% across the set. If your estimate needs a fudge factor to look right, the
*complexity classification* is wrong — not this table.

**Scope note:** dev-hours, billed tokens and calendar days are **three independent estimates**.
Never convert one into another. Hours come from cadence + throughput; tokens come from turn
count; calendar comes from availability. A project can be token-cheap and hour-expensive, or
the reverse.

### State of the Art (why the numbers below are shaped this way)

Three findings from the literature drive this section. Do not silently drop them.

| Finding | Source | Consequence for this skill |
|---------|--------|----------------------------|
| **Session-gap heuristic is the standard way to get hours out of git.** Group a developer's commits into sessions; a gap ≤ *G* continues the session, a larger gap opens a new one; each session is credited *F* extra minutes for the work before its first commit. Defaults `G = F = 120 min`. Empirical work uses ~3h boundaries — well above the ~13 min median inter-commit gap, well below overnight gaps. | [git-hours](https://github.com/kimmobrunfeldt/git-hours), [git-estimate](https://github.com/luigitni/git-estimate), [commit-cadence analysis](https://betterprogramming.pub/measuring-the-cadence-of-commits-in-git-history-ed58590a3b0e) | `scripts/git-hours.py` implements it. **Run it on any repo you have** instead of guessing hours/day. |
| **Git metrics approximate effort at best ~61% correlation** — never a substitute for measurement. | [GitClear productivity guide](https://www.gitclear.com/measuring_developer_productivity_a_comprehensive_guide_for_the_data_driven), [Contribution Rate Imputation Theory](https://arxiv.org/pdf/2410.09285) | Quote a **band**, never a point number. Never sell hours as measured when they were derived. |
| **Self-reported AI speedup is systematically wrong.** In a randomized controlled trial, experienced devs were **19% slower** with AI while believing they were 20% faster. | [METR, Jul 2025](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/), [summary](https://www.seangoedecke.com/impact-of-ai-study/) | Never discount hours for "AI makes it faster" on a mature, ≥100k-LOC codebase. Apply the AI factor table below. |

**AI-assistance factor (applies to dev-hours, not calendar days):**

| Context | Hours multiplier | Rationale |
|---------|-----------------|-----------|
| Greenfield / scaffolding / boilerplate | 0.5–0.7x | Where the observed throughput gains are real |
| New feature in a small-to-mid codebase (<100k LOC) | 0.85x | Modest gain |
| Mature repo the dev knows well, ≥100k LOC | **1.19x** | METR RCT: measured *slowdown*, not speedup |
| Unfamiliar codebase / ambiguous spec | 0.8x | AI helps with orientation |

### Measure First, Estimate Second

If **any** comparable repository exists (same team, same stack, prior version), do not use the derived tables — measure:

```bash
python3 scripts/git-hours.py --repo /path/to/comparable-repo --since '1 year ago'
```

Output gives `commits`, `hours`, `active days`, `c/day` and `h/day` per author. Feed the observed `h/day` straight into the cadence estimator, replacing the profile table. Tune `--max-gap` / `--first-commit` if the team's commit style is unusual (many tiny commits → lower `--first-commit`).

The tables above are measured on *this* user's 6 repos; they are the **fallback when no closer comparable exists**.

**Two independent estimators — always compute both and reconcile:**

1. **Cadence estimator** (primary):
   ```
   dev_hours = project_working_days × hours_per_active_day
   ```
   `hours_per_active_day` = measured value from `git-hours.py` when a comparable repo exists, otherwise **5.5** (band 5.0–7.0). Do **not** vary it by rhythm — the measurement says rhythm doesn't move it.

2. **Throughput estimator** (cross-check) — **measured** net committed LOC per hour across the same 6 repos (lockfiles, `node_modules`, `dist/`, `vendor/`, `.min.`, `.json`, `.snap` excluded):

   | Net LOC | Hours | **LOC / h** | Character |
   |---------|-------|-------------|-----------|
   | 50,181 | 39.2 | **1,280** | Scaffold-heavy burst |
   | 224,796 | 180.9 | **1,243** | Codegen + sustained burn |
   | 116,241 | 125.9 | **923** | Multi-module monorepo |
   | 126,347 | 174.8 | **723** | Full-stack + polish loops |
   | 185,164 | 275.5 | **672** | Multi-phase platform |
   | 47,124 | 149.0 | **316** | Frontend polish-heavy |

   **Median 823 LOC/h. Band 300–1,300.** Pick by character, not by feature tier:

   | Project character | LOC / h |
   |-------------------|---------|
   | Frontend/UI polish-heavy, many small fix commits | ~320 |
   | Full-stack app with review loops | ~700 |
   | Backend / monorepo, moderate boilerplate | ~900 |
   | Scaffold- or codegen-heavy | ~1,250 |
   | **No signal → use median** | **~820** |

   ```
   dev_hours = total_net_committed_LOC / loc_per_hour[character]
   ```

   > LOC counts here are **net** (added − deleted) and exclude generated files; do not feed raw `git diff --stat` totals into it.

**Reconciliation rule:**

| Cadence vs throughput | Action |
|-----------------------|--------|
| Within 1.5x | Quote the range between them. Done. |
| 1.5–2.5x apart | Take the **higher**. Under-estimation is the observed failure mode. |
| >2.5x apart | Wrong tier or wrong rhythm. Re-do Step 7.2 (complexity) and 7.4 (rhythm). |

**Team scaling:** the hours above are *one developer's* hours. For N devs, calendar days shrink sub-linearly (Brooks) while dev-hours **grow**:

| Team size | Calendar-day divisor | Dev-hours multiplier |
|-----------|---------------------|----------------------|
| 1 | 1.0 | 1.00 |
| 2 | 1.6 | 1.15 |
| 3 | 2.1 | 1.30 |
| 4+ | 2.5 | 1.50 |

### Wall-Clock Formula

Run `python3 scripts/estimate-cost.py --turns N --features ... --rhythm ...` for the arithmetic; the formula below is the spec it implements.

```
feature_days(median) = span_table[complexity]
project_calendar_days = Σ feature_days × rhythm_multiplier × (1 + polish_loop_rate × 0.5)
project_working_days = project_calendar_days × working_day_factor      # factor = active_days_per_week / 7

# hours: rhythm multiplier is ALREADY inside project_working_days — never re-apply it here
dev_hours_cadence    = project_working_days × hours_per_active_day     # default 5.5, band 5.0-7.0
dev_hours_throughput = net_committed_LOC / loc_per_hour[character] # default 820
dev_hours_raw        = reconcile(cadence, throughput)                  # see reconciliation rule
dev_hours            = dev_hours_raw × ai_factor[context] × team_multiplier[N]
```

Optional billing line, only when the user supplies an hourly rate:
```
dev_cost_usd       = dev_hours × hourly_rate
total_project_cost = dev_cost_usd + ai_token_cost_usd
```

**Always quote calendar days, working days AND dev-hours** — stakeholders care about calendar ("when can I see it"), the team cares about working days, finance cares about hours.

### Sanity Check Against Historical Projects

| Your estimate | Compare against |
|---------------|-----------------|
| Small web app (5–10 features) | 53 features / 117 days / 15.6 c/wk (sprint-and-rest) |
| Full-stack MVP (15–20 features) | 18 features / 130 days / 16.2 c/wk (polish-heavy) |
| AI agent pipeline (30+ features) | 38 features / 22 days (sustained burn) |
| Multi-module platform (15+ cats) | phases of 9–41 days each (multi-phase) |

If your estimate diverges >2x from these anchors, re-check:
- Are you double-counting polish loops?
- Did you apply the rhythm multiplier?
- Are "burst days" hiding working-day effort?

### Out-of-Band Warning (Reclassify Check)

Prompts framed as "Medium MVP" or "small web app" often carry 20–30k LOC of scope, which is the **Large app** band. After computing total LOC, look up the actual band in the Project Size Reference Table (above). If your computed LOC is 2x or more above the band implied by the user's framing, flag it explicitly in the estimative:

````markdown
## ⚠️ Reclassify Check

- Prompt framing: "Medium MVP" → expected band: 5–15k LOC / 150–700 turns / $20–$91
- Computed: ~26k LOC / ~1,100 turns / ~$143
- Computed is 1.7x above the implied band → **reclassify as Large app**
- Action: confirm with user whether scope is correct before proceeding
````

This single check catches the #1 estimation error: under-classification by the prompt author.

### Model-Mix Strategy (Cost Optimization)

Real savings come from **mixing models by task type**:

| Task type | Recommended model | Why |
|-----------|-------------------|-----|
| CRUD, migrations, scaffolding, configs | DeepSeek V3.2 or Gemini 2.5 Flash Lite | Mechanical patterns, <$1/M output, no reasoning needed |
| Bug fixes, refactors, polish loops | MiniMax M2.5 or Sonnet 5 | Need some reasoning, balance cost/quality |
| Architecture decisions, novel patterns | Current Sonnet- or Opus-tier Claude | Reasoning matters here |
| Smart contracts, security-critical | Current Opus-tier Claude only | Cost is not the constraint |

**Rule of thumb for greenfield SaaS:** expect ~60% of work to be CRUD/scaffolding (cheap model), ~25% refactor/polish (mid model), ~15% architectural (premium model). Splitting this way cuts total cost by 50-70% vs uniform-Sonnet.

Example split for a 26k-LOC greenfield SaaS (~1,100 turns, cache-aware pricing):
- 60% (660 turns) on a budget model: ~$3
- 25% (275 turns) on Sonnet 5: ~$11
- 15% (165 turns) on Opus 5: ~$21
- **Total: ~$35** vs uniform-Opus ~$143 → **~75% savings**

> Caveat: the mix only pays off if the cheap tier does not increase the **turn count**. A
> budget model that needs 3 turns where Opus needs 1 is more expensive, not less. Never
> claim mix savings without a turn-count assumption stated next to them.

Compute the model mix separately and present both the single-model upper bound and the mix.

**Automated mix calculation:** Use the bundled script `scripts/optimize-model-mix.py` for exact per-category splits:

```bash
# Default balanced mix
python3 scripts/optimize-model-mix.py --turns 1100

# Quality tier variants
python3 scripts/optimize-model-mix.py --turns 230 --quality budget      # 60-80% savings
python3 scripts/optimize-model-mix.py --turns 2000 --quality premium    # Opus-heavy, 20-30% savings
python3 scripts/optimize-model-mix.py --turns 90 --quality ultra-budget # 80%+ savings

# Refresh prices from llmgateway GitHub (monthly)
python3 scripts/optimize-model-mix.py --fetch --turns 400
```

The script caches prices in `/tmp/model_prices.json` (refresh with `--fetch`). It reads from the same llmgateway aggregator referenced in the Top Market Models section, so the prices stay in sync.

The script prices with the same cache-aware turn model as `estimate-cost.py`; its all-Opus line must match that script's median within rounding. Report both the single-model upper bound and the mix.

### When to Override the Mix

- **Single-agent workflow** (you use one model for everything): drop the mix — just pick the cheapest tier that meets quality needs
- **Latency-critical** (interactive coding, real-time responses): premium tier pays for itself with fewer iterations
- **Security/financial code** (smart contracts, payments): critical = 100% Opus regardless of cost
- **Exploration/prototyping** (don't know yet what you're building): start at ultra-budget, scale up if quality issues surface

### Greenfield Mode (No Existing Repo)

The Prerequisites section assumes `rtk init` runs against an existing codebase. For greenfield prompts (spec only, no repo yet), adapt:

1. **Skip Step 3 file identification** — there's nothing to scan. Instead, derive file counts from the spec: typical greenfield projects have ~1 file per 150 LOC of source + 1 file per 200 LOC of tests + 1 file per 100 LOC of docs/configs.
2. **Skip LOC measurement** — estimate from spec instead. Use these anchors per feature:
   - Simple CRUD: ~500 LOC
   - Single module with business logic: ~1,500 LOC
   - Multi-module with integration: ~5,000 LOC
   - Full-stack feature (frontend + backend + tests): ~2,500 LOC
   - Infrastructure/devops: ~800 LOC
3. **Use spec-based complexity classification** — assign each spec'd feature a complexity tier based on the descriptions, not on measured LOC.
4. **Treat LOC estimates as ±30%** — greenfield is inherently uncertain. State the band explicitly.
5. **All other steps unchanged** — token/cost/time math works identically; only inputs differ.

---

## Token-Saving Recommendations

Cost = turns × context size. Only two levers exist: **fewer turns**, or **smaller context per
turn**. Ranked by measured impact:

- [ ] **Cut turns first.** A failed turn costs the same as a good one. Clear specs and
      acceptance criteria up front beat any context trick.
- [ ] **Keep the cache warm.** 97 % of input bills at 0.10×. Anything that invalidates the
      prefix (reordering context, editing early files, restarting cold) re-bills at 1.25×.
- [ ] Use selective context — only load files relevant to the current task
- [ ] When debugging, paste only relevant error lines (not full stack traces)
- [ ] Break large files (600+ lines) before asking AI to modify them
- [ ] For boilerplate-heavy frameworks (SeaORM, Prisma): create "Type Summaries" instead of
      sending full generated code
- [ ] Summarize decisions and start a clean session when context stops being relevant — but
      note a cold start pays full cache-write price, so do it on a task boundary, not mid-loop

---

### Step 7 — Wall-Clock & Dev-Hours Calibration (Time Estimation)

This step converts the token/cost estimate into calendar time **and dev-hours** using real data from 6 calibration repos. Without it, "estimated cost" is useless — what the user actually wants to know is "when is it done, and how many hours does it bill?"

**Procedure:**

1. **Decompose the project into unit features.** Not categories (frontend, backend) — atomic features that one commit-batch could complete. Use the same decomposition as Step 3, but smaller-grained. Example: "Auth with Google OAuth" is one feature, not "auth" as a whole.

2. **Classify each feature's complexity:**
   - **trivial** (rename, 1-line fix, doc typo)
   - **simple** (isolated config, small util, single test)
   - **medium** (single module, CRUD page, ~1-2k LOC, fix-loop)
   - **complex** (multi-module, design decisions, ~5k LOC)
   - **critical** (architecture, full-stack, RAG, multi-agent, ~10k+ LOC)

3. **Apply span table.** Pull `median span` from the calibration table:
   - trivial → 1d
   - simple → 1d
   - medium → 2d
   - complex → 8d
   - critical → 28d

4. **Identify rhythm profile.** Decide which pattern matches:
   - **Sustained burn** — solo AI-assisted, daily commits, no off-days expected → 1.0x
   - **Sprint-and-rest** — work in 3-7d bursts → 1.4x
   - **Build + tail** — heavy phase then 1-2 commits/month → 1.6x
   - **Burst + gap + consolidation** — phases with month-long gaps → 1.8x
   - **Polish-loop heavy** — review-fix-fix cycles → 1.5x

5. **Count polish loops.** Estimate what % of commits will be sub-200-LOC fix/chore:
   - <5%: 0 add
   - 5-10%: +20%
   - 10-20%: +50%
   - >20%: +100% (also flag scope concern)

6. **Compute day totals:**
   ```
   project_calendar_days = Σ(feature_span) × rhythm_multiplier × (1 + polish_loop_rate × 0.5)
   project_working_days  = project_calendar_days × working_day_factor   # factor = active_days_per_week / 7
   ```

7. **Compute dev-hours.** First check for a comparable repo — if one exists, run
   `python3 scripts/git-hours.py --repo <path>` and use the measured `h/day`. Then run **both estimators and reconcile** (see *Dev-Hours Calibration* above):
   ```
   dev_hours_cadence    = project_working_days × 5.5            # or measured h/day
   dev_hours_throughput = net_committed_LOC / 820           # or the character-matched LOC/h
   ```
   - Within 1.5x → quote the range.
   - 1.5–2.5x apart → take the higher.
   - >2.5x apart → complexity or rhythm is wrong; redo sub-steps 2 and 4.

   Then apply the **AI-assistance factor** (mature ≥100k-LOC repo = 1.19x *slower*, per the METR RCT — do not discount) and the **team-size multiplier** if the project is not solo. Add the billing line **only** if the user gave an hourly rate.

8. **Sanity check** against reference projects (table in Time section above). If estimate is >2x off from anchor, re-check steps 3-5. Cross-check hours against the measured set: a solo full-time month of committed work ≈ **110–140 h** (22 active days × 5.5), and the largest calibration repo (185k net LOC) cost **275 h**. An estimate claiming 500 h for a 50k-LOC app is wrong.

**Output to `{slug}-estimative.md`** (extends the template):

````markdown
## Time & Wall-Clock Estimate

| Feature | Complexity | Span (days) | Net LOC est |
|---------|-----------|-------------|------------------|
| {feature 1} | medium | 2 | 1,200 |
| {feature 2} | complex | 8 | 4,500 |
| ... | ... | ... | ... |

- **Σ base feature-days:** {N}
- **Rhythm profile:** {profile}
- **Rhythm multiplier:** {1.0-1.8x}
- **Polish-loop rate:** {0-100%} → adjustment {0-100%}
- **Calendar days:** {final N}
- **Working (active) days:** {calendar × working_day_factor}
- **Anchor sanity check:** vs {closest anchor repo}, ratio {X}

## Dev-Hours Estimate

- **Hours / active day:** {5.5 default | measured N} h (band 5.0–7.0)
- **Cadence estimator:** {working_days} × {h/day} = **{N} h**
- **Throughput estimator:** {net LOC} / {LOC-per-h for character} = **{N} h**
- **Divergence:** {X}x → {quote range | take higher | redo classification}
- **AI-assistance factor:** {0.5-1.19}x ({context})
- **Team size:** {N} → calendar ÷{divisor}, hours ×{multiplier}
- **➡️ Dev-hours (final):** **{lo}–{hi} h** ({N} person-days @ 8h)
- **Basis:** {measured via scripts/git-hours.py on <repo> | derived from calibration tables}
- **Derivation note:** when derived, hours come from commit cadence + LOC throughput, not tracked timesheets. Git metrics correlate with effort at ~61% — treat the band as a band.

### Total Cost (only if hourly rate provided)
- Dev cost: {hours} h × ${rate}/h = **${N}**
- AI token cost: **${N}**
- **Total: ${N}**

## Audit timeline (if applicable)
- {N weeks} for {tier} audit
````

---

## File Naming Convention

Always use the user-provided slug:
- `{slug}-paths.md`
- `{slug}-plan.md`
- `{slug}-steps.md`
- `{slug}-estimative.md`

**Overwrite semantics:** a re-run replaces all four files. Step 0 rotates the previous
generation to `{slug}-*.prev.md` (one level of history, overwritten in turn). Never append a
new estimate to an old file and never keep timestamped variants — one current estimate, one
previous, nothing else.

## Progress Tracking

After each step, update `{slug}-steps.md` with:
- Status (pending/in_progress/done)
- What was found
- Any blockers
