---
name: estimator
description: Multi-step project estimation with intermediate result saving. Estimates tokens, USD cost, dev-hours, AND wall-clock calendar time calibrated against 6 real repos (astral, eapbuild, rodrigo-engine, med_tool, quartinhobh, umcentavo). Saves paths.md, plan.md, steps.md, and estimative.md.
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

---

## Token Counting Methodology

### Tokens Per Line by Language

| Language / Type | Tokens/Line (avg) | Dense Code* | Tokens/100 Lines | Chars/Token |
|-----------------|-------------------|-------------|-------------------|-------------|
| Python | ~10 | ~12 | ~1,000 | ~4.2 |
| JavaScript | ~7–8 | ~10 | ~700–800 | ~4.0 |
| TypeScript (typed) | ~9–10 | ~13 | ~900–1,000 | ~3.8 |
| Svelte 5 (runes + TS) | ~10–12 | ~14 | ~1,000–1,200 | ~3.8 |
| Rust (simple) | ~10–12 | ~14 | ~1,000–1,200 | ~3.8 |
| Rust (macros/generics/lifetimes) | ~14–16 | ~18 | ~1,400–1,600 | ~3.5 |
| Solidity / Smart Contracts | ~12–14 | ~16 | ~1,200–1,400 | ~3.6 |
| Java / C# / Go | ~9–11 | ~13 | ~900–1,100 | ~3.8–4.2 |
| SQL / Config files | ~11–12 | ~12 | ~1,100–1,200 | ~3.5 |
| MASM / Assembly | ~8–10 | ~12 | ~800–1,000 | ~4.0 |
| Mixed codebase (avg) | **~10** | ~14 | ~1,000 | ~3.8 |

*\*Dense Code = macros, generics, complex types, derive attributes, interface types, runes*

**Default rule:** `Total code tokens = Total LOC x 10`

**For Rust/Solidity/complex TS:** `Total code tokens = Total LOC x 14`

> **Why higher for Rust?** `#[derive(Debug, Clone, Serialize)]`, generics like `impl<T: AsRef<str> + Send + Sync>`, and lifetime annotations (`'a`, `'static`) are tokenizer-expensive. A single Rust derive line can consume 15-20 tokens. SeaORM entities and Axum handlers with extractors push this even higher.

### File Context Overhead

Each file loaded into context adds metadata (filepath, separators, XML tags):

```
File overhead = Number of files x 150 tokens
```

### Base Code Token Formula

```
Code tokens = (Total LOC x tokens_per_line) + (Number of files x 150) + Prompt overhead
```

Where `tokens_per_line` = 10 (default) or 14 (Rust/Solidity/complex TS). Use the Dense Code column for projects heavy on macros, generics, or complex types.

- **Total LOC** = sum of all source files (exclude node_modules, build/, .git, target/, etc.)
- **Prompt overhead** = system prompt + instructions + conversation history (500–5,000 tokens per request)

### Context Repetition Tax

The AI does NOT just read your code once. Every interaction re-sends context:

```
Context cost = File tokens x Number of interactions about that file
```

Example: A 5,000-token file discussed over 10 prompts = **50,000 tokens minimum** (not 5,000).

### Reiteração Tax (The Real Killer)

In real development, the **input/output ratio is heavily skewed toward input**:

| Phase | Input:Output Ratio | Why |
|-------|-------------------|-----|
| Initial build | 3:1 | Context + instructions >> generated code |
| Debugging cycle | 8:1 | Re-sending code + errors + logs repeatedly |
| Refactoring | 5:1 | Reading existing code to rewrite portions |
| Long project (20+ weeks) | 10:1 | Accumulated context re-sends across sessions |

**The cycle:**
1. You send context (Input)
2. Model generates code (Output)
3. `cargo check` / `tsc` fails
4. You re-send code + error (Input x2)
5. Model corrects (Output x2)
6. Repeat 3-5 times per feature

```
Real Input = Base code tokens x Reiteração multiplier

| Project Duration | Reiteração Multiplier |
|-----------------|----------------------|
| 1-2 weeks       | 3x                   |
| 1-2 months      | 5x                   |
| 3-6 months      | 8x                   |
| 6+ months       | 12x                  |
```

> **Dica:** Para frameworks com boilerplate pesado (SeaORM entities, Prisma schemas), crie "Resumos de Tipos" (header files conceituais) em vez de enviar o código gerado completo. Isso pode reduzir o custo de reiteração em 40-60%.

---

## The Iceberg Model: Real Cost Distribution

For a real software project, the final code is just the tip:

| Layer | % of Total Cost | What It Includes |
|-------|----------------|-------------------|
| **Code Output** | 5-10% | Final generated code |
| **File Context (Input)** | 35-45% | Code read into context repeatedly |
| **Reiteração (debug/fix cycles)** | 25-35% | Error → re-send → fix → repeat |
| **Conversation + Planning** | 15-25% | Architecture, decisions, prompts |

### The 10x Rule

```
Real project cost ≈ Final code tokens x 10
```

For **Rust/Solidity** projects (stricter compilers, more fix cycles):
```
Real project cost ≈ Final code tokens x 15
```

This accounts for all invisible layers: planning, context loading, debugging, iteration, and polish.

---

## Phase-Based Token Budgets

### Phase 1: Planning & Discovery (Blueprint)

No code generated — tokens consumed by requirements, architecture, and decisions.

| Activity | Token Range |
|----------|------------|
| Requirements definition | 2,000 – 10,000 per session |
| Architecture & data schema | 5,000 – 15,000 (with iterations) |
| Stack choice / trade-offs | 3,000 – 7,000 |
| **Phase 1 budget** | **20k – 50k tokens** |

### Phase 2: Core Skeleton (Implementation)

Building the initial structure. Each round = 1-3 files + task + AI response.

| Project Size | Files | LOC | Phase 2 Budget |
|-------------|-------|-----|----------------|
| Small | 5–10 | 2k–5k | 50k – 300k |
| Medium | 20–50 | 5k–15k | 300k – 800k |
| Large | 50+ | 15k+ | 800k – 2M+ |

Budget = `Code tokens x 3–5` (for iterations and re-reads).

### Phase 3: Features & Polish (Scaling)

Each new feature adds its own tokens + conversation overhead:

| Activity | Tokens per Interaction | Frequency | Total (Medium Project) |
|----------|----------------------|-----------|----------------------|
| Logic explanation | 1,000 – 3,000 | High | 100k – 300k |
| Debugging (pasting logs) | 2,000 – 8,000 | Medium | 200k – 500k |
| Refactoring / review | 4,000 – 10,000 | Low | 150k – 300k |

Each new 1,000–2,000 LOC feature ≈ **10k–30k extra tokens** in chats.

### Phase 4: Testing & Documentation

| Activity | Token Range |
|----------|------------|
| Unit tests | 1:1 ratio with source code (same volume) |
| Documentation (README, API docs) | 5,000 – 20,000 |
| CI/CD and Docker config | 2,000 – 10,000 |

---

## Iterative Build Multiplier

After calculating base code tokens, apply a multiplier based on build style:

| Build Style | Multiplier | When to Use |
|-------------|-----------|-------------|
| Clean build from existing architecture | 3x | Templates, well-known patterns |
| Standard iterative build | 5x | Typical feature development |
| Heavy discovery + many iterations | 8x | Novel architecture, R&D, complex debugging |

```
Total build tokens = Code tokens x Multiplier
```

---

## Complexity Multiplier (Reasoning Tokens)

For models with extended thinking (Claude Opus, Sonnet with thinking):

| Complexity | Multiplier | Examples |
|-----------|-----------|----------|
| **Simple** | 2x output | CRUD, config, straightforward patterns |
| **Medium** | 5x output | Design decisions, some research needed |
| **Complex** | 10x output | Novel architecture, lifetimes in Rust, crypto/blockchain |
| **Critical (auditable)** | 15x output | Smart contracts, financial logic, security-sensitive code |

```
Reasoning tokens = Output tokens x Complexity multiplier
```

**Note:** Rust, Solidity, MASM, and complex type systems tend toward higher multipliers due to lifetimes, ownership, reentrancy guards, and dense type explanations. Smart contracts additionally require formal correctness reasoning.

---

## Model Pricing (USD per 1M tokens)

### Claude (Anthropic)

| Model | Input | Output | Extended Thinking | Context |
|-------|-------|--------|-------------------|---------|
| Opus 4.6 | $5.00 | $25.00 | $25.00 | 1M |
| Sonnet 4.6 | $3.00 | $15.00 | $15.00 | 1M |
| Haiku 3.5 | $0.25 | $1.25 | $1.25 | 200k |

### Top Market Models (Calibrated 2026-08-27)

> **Source:** llmgateway.io aggregator (GitHub: `theopenco/llmgateway`) — aggregates official prices from 40+ providers. Prices verified via raw GitHub source `packages/models/src/models/*.ts`. Updated monthly by community; pull before estimating.

**Tier 1 — Premium (quality matters most)**

| Model | Input | Output | Context | Notes |
|-------|-------|--------|---------|-------|
| Claude Opus 4.6 | $5.00 | $25.00 | 200k | Stable premium tier, identical pricing to Opus 4.5/4.7/4.8/5 |
| Claude Opus 5 | $5.00 | $25.00 | 200k | Latest Opus, same pricing (Anthropic price-stable) |
| Claude Fable 5 | $10.00 | $50.00 | 1M | **New** top tier — 2x Opus price, 5x context |
| Gemini 3 Pro Preview | $2.00 | $12.00 | 1M | Google flagship, 1M context |

**Tier 2 — Balanced (default for most projects)**

| Model | Input | Output | Context | Notes |
|-------|-------|--------|---------|-------|
| Claude Sonnet 4.6 | $3.00 | $15.00 | 200k | Stable mid-premium |
| Claude Sonnet 5 | $2.00 | $10.00 | 200k | **33% cheaper than 4.6**, latest |
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

### Quick Cost Comparison (per 1M tokens, input+output combined, 75/25 split)

| Tier | Models | Combined $/1M (weighted) |
|------|--------|--------------------------|
| **Free** | Qwen Turbo (free tier), StepFun 3.5 Flash | $0–$0.15 |
| **Ultra-budget** (<$1) | Gemini 2.5 Flash Lite, Mistral Small 3.2, DeepSeek V4 Flash, Grok 4.1 Fast | $0.18–$0.65 |
| **Budget** ($1–$5) | Mistral Large 3, MiniMax M2.5/M2.7, Gemini 3 Pro, GLM-4.5 Air | $0.88–$6.00 |
| **Mid-range** ($5–$20) | Claude Sonnet 5, Sonnet 4.6, GLM-5, Grok 4 | $4.50–$18.00 |
| **Premium** ($20+) | Claude Opus 4.6/5, Claude Fable 5 | $30.00–$60.00 |

### Cost Calculation Formula
```
Total Cost = (Input x input_price + Output x output_price + Reasoning x reasoning_price) / 1,000,000
```

> **Note on Haiku:** Claude 3.5 Haiku is now $0.80/$4.00 (not the legacy $0.25/$1.25). New Haiku 4.5 = $1.00/$5.00. Don't use old Haiku 3 pricing in current estimates.

### Model Selection Guide

| Project Type | Recommended (2026-08) | Why |
|-------------|------------------------|-----|
| Quick prototype / script | Mistral Small 3.2, Gemini 2.5 Flash Lite | $0.10-0.30/M, good enough for simple code |
| Medium MVP | Claude Sonnet 5 (new default) | 33% cheaper than 4.6, latest gen |
| Complex system (Rust, crypto, agents) | Claude Opus 4.6 | Stable, no premium tier jump |
| Budget-constrained, high volume | Grok 4.1 Fast, DeepSeek V4 Flash | 2M context + sub-$0.50/M |
| Reasoning-heavy / math | Grok 4, Gemini 2.5 Pro | Strong at structured output |
| Long-context (RAG, big codebases) | Llama 4 Scout (10M), Gemini 2.5 Flash Lite (1M) | Largest contexts available |
| Complex system (Rust, crypto, agents) | Opus 4.6 | Best reasoning for complex logic |
| Budget-constrained, high volume | Grok 4.1 Fast, MiniMax M2.5 | Low cost + large context |
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

Running AI-assisted analysis before formal audit reduces cost:

| Activity | Token Cost | Purpose |
|----------|-----------|---------|
| Static analysis prompts | 50k–200k | Reentrancy, overflow, access control |
| Invariant generation | 30k–100k | Property-based test suggestions |
| Gas optimization review | 20k–80k | Storage patterns, loop optimization |
| Documentation for auditors | 40k–150k | Spec, threat model, architecture docs |

```
Pre-audit AI tokens = Contract LOC x 30–50 (includes multiple review passes)
```

> **Important:** AI pre-audit does NOT replace formal audit. It reduces audit time (and cost) by catching low-hanging issues first.

### Including Audit in Total Estimation

```
Total project cost = Development cost + Pre-audit AI cost + Formal audit cost
```

Always flag smart contract projects in the estimation output with audit requirements.

---

## Project Size Reference Table

| Project Type | Files | LOC | Code Tokens | Real Total (x10/x15) | Cost Range (Sonnet) | Audit? |
|-------------|-------|-----|-------------|----------------------|---------------------|--------|
| Script / CLI tool | 3–10 | 500–2k | 5k–20k | 50k–200k | $0.50–$3 | — |
| Small web app | 10–20 | 2k–5k | 20k–50k | 200k–500k | $3–$8 | — |
| Medium MVP (web/desktop) | 20–50 | 5k–15k | 50k–150k | 500k–1.5M | $8–$25 | — |
| Large app | 50–100 | 15k–50k | 150k–500k | 1.5M–5M | $25–$80 | — |
| Complex system (agents) | 100+ | 50k+ | 500k+ | 5M–10M+ | $80–$200+ | — |
| Smart contract (small) | 5–15 | 500–2k | 7k–28k | 100k–420k (x15) | $2–$8 | $5k–$15k |
| Smart contract (DeFi) | 15–40 | 2k–10k | 28k–140k | 420k–2.1M (x15) | $8–$40 | $30k–$80k |
| Smart contract (protocol) | 40–100+ | 10k–30k+ | 140k–420k+ | 2.1M–6.3M+ (x15) | $40–$120+ | $80k–$500k+ |

---

## Workflow

### Step 0 — Get the slug

Ask the user for a project slug (e.g., "my-api-project", "react-dashboard").

Initialize `{slug}-steps.md`:
```markdown
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

## Step 4: Estimate Lines
- Status: pending|done
- Notes:

## Step 5: Calculate Tokens
- Status: pending|done
- Notes:

## Step 6: Final Estimation
- Status: pending|done
- Notes:

## Step 7: Wall-Clock Calibration (Time Estimation)
- Status: pending|done
- Notes: For each unit-feature, classify complexity (trivial/simple/medium/complex/critical) and apply the span table. Compute rhythm multiplier (sustained/sprint-and-rest/build+tail/burst+gap/polish-heavy). Count polish-loop rate. Output calendar days + working days + dev-hours (cadence vs throughput, reconciled).
```

---

### Step 1 — Analyze Prompt

Understand the user's idea/prompt:
1. What is the goal?
2. What type of project? (API, webapp, CLI, library, etc.)
3. What technologies/languages?
4. What features?
5. What complexity level? (simple/medium/complex)

Save analysis to `{slug}-plan.md`:
```markdown
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
- API spec: {estimated tokens}
- Data models: {estimated tokens}
- README: {estimated tokens}

### Research Token Estimate
- Web searches: ~{n} queries x ~{m} tokens = ~{total}
- Docs reading: ~{n} docs x ~{m} tokens = ~{total}
- Code analysis: ~{n} files x ~{m} tokens = ~{total}
- **Subtotal Research**: ~{total} tokens
```

Update `{slug}-steps.md`.

---

### Step 6 — Final Estimation

Create `{slug}-estimative.md`:
```markdown
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

## Base Token Calculation

### Code Tokens (Iceberg Tip — 10%)
| Category | Files | Lines | Tokens/Line | Tokens |
|----------|-------|-------|-------------|--------|
| Config | 3 | 100 | 9 | 900 |
| Source | 10 | 1,500 | {by-lang} | {calc} |
| Tests | 5 | 800 | {by-lang} | {calc} |
| Docs | 2 | 200 | 9 | 1,800 |
| **Total** | 20 | 2,600 | — | **{total}** |

### File Overhead
- {n} files x 150 = {total} tokens

### Base Code Tokens
- Code: {code_tokens}
- File overhead: {file_overhead}
- **Base total**: {sum}

## Real Cost Estimation (The Full Iceberg)

### Phase Breakdown
| Phase | Budget | Tokens |
|-------|--------|--------|
| Planning & Discovery | 20k–50k | ~{n} |
| Core Skeleton (code x 3-5) | — | ~{n} |
| Features & Iteration | — | ~{n} |
| Testing (1:1 with source) | — | ~{n} |
| Documentation & CI/CD | 7k–30k | ~{n} |
| **Grand Total** | — | **~{n}** |

### Sanity Check (10x / 15x Rule)
- Code tokens: {n}
- Multiplier: x10 (standard) or x15 (Rust/Solidity)
- Sanity total: {n}
- Matches phase breakdown: yes|no (adjust if needed)

### Reiteração Analysis
- Project duration: {weeks/months}
- Reiteração multiplier: {3x|5x|8x|12x}
- Estimated real input: {base_code_tokens x reiteração_multiplier}
- Input:Output ratio: {estimated, e.g. 5:1}

### Build Multiplier Applied
- Build style: clean|standard|heavy
- Multiplier: {3|5|8}x
- Code tokens x multiplier = {total}

## Cost Estimation (USD)

| Model | Input Cost | Output Cost | Reasoning Cost | Total |
|-------|------------|-------------|----------------|-------|
| Opus 4.6 | ${x} | ${x} | ${x} | **${x}** |
| Sonnet 4.6 | ${x} | ${x} | ${x} | **${x}** |
| Haiku 3.5 | ${x} | ${x} | ${x} | **${x}** |
| DeepSeek V3.2 | ${x} | ${x} | — | **${x}** |
| Gemini 2.5 Flash Lite | ${x} | ${x} | — | **${x}** |

**Recommended model for this project:** {model} — {reason}
**Budget alternative:** {model} — {reason}

## Smart Contract Audit (if applicable)

| Item | Estimated Cost | Notes |
|------|---------------|-------|
| AI pre-audit tokens | {n} tokens (~${x}) | Static analysis, invariants, gas review |
| Formal audit (external) | ${x} | Based on {LOC} LOC, {tier} tier |
| **Total with audit** | **${dev + audit}** | Development + audit combined |

*Omit this section for non-smart-contract projects.*

## Time & Wall-Clock Estimation (Calibrated)

> **Calibration source:** 6 real repos mined by git history (astral_project, eapbuild, rodrigo-engine, med_tool, quartinhobh, umcentavo_monorepo), 132 unit-features aggregated. Numbers below are observed, not guessed.

### Feature-Span Calibration (Calendar Days, First→Last Commit)

> Each row is observed median across unit-features in the calibration set. **Sustained-burn projects** (rodrigo_engine pattern) show low per-feature spans because all features ship within 1-3 active days — the project's total calendar duration is captured by the SUM of feature spans, not by any single feature's span.

| Complexity | Median span | Mean span | p90 span | LOC median | n (features) | Example profile |
|------------|-------------|-----------|----------|-----------|--------------|-----------------|
| **trivial** (rename, typo, 1-line) | 1d | 0.3d | 1d | ~0 | 2+ | All profiles |
| **simple** (small util, isolated config) | 1d | 0.5d | 2d | 465 | 9 | All profiles |
| **medium** (single module, CRUD, fix-loop) | 2d | 3d | 8d | 1,500 | 28 | quartinhobh, eapbuild |
| **complex** (multi-module, design decisions) | 8d | 12d | 28d | 5,000 | 15+ | quartinhobh, umcentavo |
| **critical** (architecture, multi-agent, RAG, full-stack) | 28d | 30d | 60d+ | 12,000+ | 5+ | eapbuild, rodrigo (xlarge) |

**Reference data per repo:**

| Repo | Span (days) | Features | Same-day % | ≤7d % | ≤30d % | Median span |
|------|-------------|----------|------------|-------|--------|-------------|
| rodrigo_engine | 22 | 38 | 87% | 100% | 100% | 1d |
| med_tool | 39 | 28 | 100% | 100% | 100% | 1d |
| eapbuild | 130 | 18 | 12% | 50% | 88% | 8d |
| quartinhobh | 117 | 53 | 32% | 49% | 75% | 8d |
| umcentavo | 114 | 33 | 21% | 48% | 64% | 8d |
| astral_project | 125 | 17 (cats) | — | — | — | phases 9–41d |

### Rhythm Profiles (Real Patterns)

Projects don't burn linearly. Identify the profile to avoid under-estimation:

| Profile | Trigger | Wall-clock multiplier | Example |
|---------|---------|----------------------|---------|
| **Sustained burn** | Daily commits, even spread | 1.0x | rodrigo_engine (16 c/day, 22d) |
| **Sprint-and-rest** | Bursts of 3–7d, then gap | 1.4x | quartinhobh (23 active / 117 cal days) |
| **Build + tail** | Heavy phase + 1–2 commits/month | 1.6x | med_tool (131 c in 2d, then tail) |
| **Burst + gap + consolidation** | 2 phases with month-long gap | 1.8x | umcentavo (Apr→Jun gap→Jul) |
| **Polish-loop heavy** | >10% commits are sub-200-LOC fix/chore | 1.5x | eapbuild (35 polish / 300 = 12%) |

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
| 10–20% | Polish-heavy (eapbuild pattern) | +50% |
| >20% | Review-fix loop not converging | +100% (and reconsider scope) |

### Working-Day Conversion

Calendar days ≠ working days. For solo/small-team estimation:

**Measured** — active days counted as distinct commit-days per repo (`scripts/git-hours.py`):

| Rhythm | Anchor repo | Active days / calendar days | Active days per week | `working_day_factor` |
|--------|-------------|-----------------------------|----------------------|----------------------|
| Sustained burn | rodrigo-engine (21/22) | 0.95 | 6.7 | **0.95** |
| Multi-phase platform | astral_project (49/125) | 0.39 | 2.7 | **0.39** |
| Polish-loop heavy | eapbuild (28/130) | 0.22 | 1.5 | **0.22** |
| Sprint-and-rest | quartinhobh (25/117) | 0.21 | 1.5 | **0.21** |
| Build + tail | med_tool (8/39) | 0.21 | 1.4 | **0.21** |
| Burst + gap + consolidation | umcentavo (23/114) | 0.20 | 1.4 | **0.20** |

> Everything except sustained burn lands at **~0.20–0.22** — roughly *1.5 active days per calendar week*. That is the honest solo-side-project rate. A prior version of this table guessed 4–6 days/week and over-stated hours by ~2.5x.

> **Rule of thumb:** Solo AI-assisted dev moves ~500–2,000 LOC net per **active day** at the "medium" tier (rodrigo_engine: 363k LOC / 22 active days = ~16k/day at xlarge tier).

### Dev-Hours Calibration (MEASURED)

> **Provenance:** hours below were **measured**, not guessed — `scripts/git-hours.py` ran the session-gap algorithm (`--max-gap 120 --first-commit 120`) over the same 6 calibration repos. Reproduce any row with:
> `python3 scripts/git-hours.py --repo /path/to/repo`
> They are still *inferred from commit timestamps*, not timesheets — so quote a band, never a point.

**Measured hours per active day (n = 6 repos, 945 h, 154 active days):**

| Repo | Rhythm profile | Commits (top author) | Hours (repo) | Active days | c / active day | **h / active day** |
|------|---------------|---------------------|--------------|-------------|----------------|--------------------|
| rodrigo-engine | Sustained burn | 281 | 180.9 | 21 | 13.4 | **7.0** |
| quartinhobh | Sprint-and-rest | 241 | 149.0 | 25 | 9.6 | **5.8** |
| astral_project | Multi-phase platform | 475 | 275.5 | 49 | 9.7 | **5.6** |
| umcentavo | Burst + gap + consolidation | 201 | 125.9 | 23 | 8.7 | **5.4** |
| eapbuild | Polish-loop heavy | 259 | 174.8 | 28 | 9.2 | **5.0** |
| med_tool | Build + tail | 95 | 39.2 | 8 | 11.9 | **4.9** |

> ### 🔑 The finding that matters
> **h/active day is nearly flat: 4.9–7.0, median 5.5 (±19%).** Rhythm profile barely moves it. What rhythm actually changes is *how many active days exist inside a calendar span* — which the calendar formula already handles.
>
> **Consequence: apply the rhythm multiplier to calendar days ONLY. Never to hours.** Doing both double-counts.

| Use case | h/active day |
|----------|--------------|
| Default (any profile, no better data) | **5.5** |
| Sustained burn / full-time focus | 7.0 |
| Part-time, tail phase, or maintenance | 4.9 |
| Band to quote | **5.0–7.0** |

*A prior version of this section guessed 9–10 h/active day. Measurement put it at 5.5 — a 40% over-estimate. Do not re-guess.*

**Back-test — the formula reproduces the measured hours on all 6 repos:**

| Repo | Calendar d | × factor | = active d | × h/day | = predicted h | Measured h | Error |
|------|-----------|----------|-----------|---------|---------------|------------|-------|
| rodrigo-engine | 22 | 0.95 | 20.9 | 7.0 | 146 | 147.5 | −1% |
| quartinhobh | 117 | 0.21 | 24.6 | 5.8 | 143 | 145.0 | −1% |
| astral_project | 125 | 0.39 | 48.8 | 5.6 | 273 | 275.5 | −1% |
| umcentavo | 114 | 0.20 | 22.8 | 5.4 | 123 | 123.9 | −1% |
| eapbuild | 130 | 0.22 | 28.6 | 5.0 | 143 | 139.4 | +3% |
| med_tool | 39 | 0.21 | 8.2 | 4.9 | 40 | 39.2 | +2% |

Within ±3% across the set. If your estimate needs a fudge factor to look right, the *complexity classification* is wrong — not this table.

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

2. **Throughput estimator** (cross-check) — **measured** net hand-authored LOC per hour across the same 6 repos (lockfiles, `node_modules`, `dist/`, `vendor/`, `.min.`, `.json`, `.snap` excluded):

   | Repo | Hand LOC (net) | Hours | **LOC / h** | Character |
   |------|---------------|-------|-------------|-----------|
   | med_tool | 50,181 | 39.2 | **1,280** | Scaffold-heavy burst |
   | rodrigo-engine | 224,796 | 180.9 | **1,243** | Generated + sustained burn |
   | umcentavo | 116,241 | 125.9 | **923** | Multi-module monorepo |
   | eapbuild | 126,347 | 174.8 | **723** | Full-stack + polish loops |
   | astral_project | 185,164 | 275.5 | **672** | Multi-phase platform |
   | quartinhobh | 47,124 | 149.0 | **316** | Frontend polish-heavy |

   **Median 823 LOC/h. Band 300–1,300.** Pick by character, not by feature tier:

   | Project character | LOC / h |
   |-------------------|---------|
   | Frontend/UI polish-heavy, many small fix commits | ~320 |
   | Full-stack app with review loops | ~700 |
   | Backend / monorepo, moderate boilerplate | ~900 |
   | Scaffold- or codegen-heavy | ~1,250 |
   | **No signal → use median** | **~820** |

   ```
   dev_hours = total_net_hand_authored_LOC / loc_per_hour[character]
   ```

   > Earlier versions of this table used 250–400 LOC/h per feature tier. Measurement says 300–1,300 at project level — the old numbers over-estimated hours by 2–4x. LOC counts here are **net** (added − deleted) and exclude generated files; do not feed raw `git diff --stat` totals into it.

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

```
feature_days(median) = span_table[complexity]
project_calendar_days = Σ feature_days × rhythm_multiplier × (1 + polish_loop_rate × 0.5)
project_working_days = project_calendar_days × working_day_factor      # factor = active_days_per_week / 7

# hours: rhythm multiplier is ALREADY inside project_working_days — never re-apply it here
dev_hours_cadence    = project_working_days × hours_per_active_day     # default 5.5, band 5.0-7.0
dev_hours_throughput = net_hand_authored_LOC / loc_per_hour[character] # default 820
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
| Small web app (5–10 features) | quartinhobh bootstrap: 53 features / 117 days / 15.6 c/wk |
| Full-stack MVP (15–20 features) | eapbuild MVP: 18 features / 130 days / 16.2 c/wk |
| AI agent pipeline (30+ features) | rodrigo_engine: 38 features / 22 days (sustained burn) |
| Multi-module platform (15+ cats) | astral_project phases: 9–41 days per phase |

If your estimate diverges >2x from these anchors, re-check:
- Are you double-counting polish loops?
- Did you apply the rhythm multiplier?
- Are "burst days" hiding working-day effort?

### Out-of-Band Warning (Reclassify Check)

> Real failure mode discovered during skill validation: prompts framed as "Medium MVP" or "small web app" often have 20-30k LOC scope that actually lands in the **Large app** band. The skill won't auto-reclassify — YOU must check.

After computing total LOC, **look up the actual band** in the Project Size Reference Table (above). If your computed LOC is 2x or more above the band implied by the user's framing, flag it explicitly in the estimative:

```markdown
## ⚠️ Reclassify Check

- Prompt framing: "Medium MVP" → expected band: 5-15k LOC / $8-25 USD
- Computed: ~26k LOC / ~$96 USD (Sonnet)
- Computed is 1.7x above the implied band → **reclassify as Large app**
- Action: confirm with user whether scope is correct before proceeding
```

This single check catches the #1 estimation error: under-classification by the prompt author.

### Model-Mix Strategy (Cost Optimization)

The skill's reference table treats model choice as one-line, but real savings come from **mixing models by task type**:

| Task type | Recommended model | Why |
|-----------|-------------------|-----|
| CRUD, migrations, scaffolding, configs | DeepSeek V3.2 or Gemini 2.5 Flash Lite | Mechanical patterns, <$1/M output, no reasoning needed |
| Bug fixes, refactors, polish loops | MiniMax M2.5 or Sonnet 5 | Need some reasoning, balance cost/quality |
| Architecture decisions, novel patterns | Sonnet 5 or Opus 4.6 | Reasoning matters here |
| Smart contracts, security-critical | Opus 4.6 only | Cost is not the constraint |

**Rule of thumb for greenfield SaaS:** expect ~60% of work to be CRUD/scaffolding (cheap model), ~25% refactor/polish (mid model), ~15% architectural (premium model). Splitting this way cuts total cost by 50-70% vs uniform-Sonnet.

Example cost split for clinic-os (26k LOC):
- 60% on DeepSeek V3.2: ~$0.40
- 25% on Sonnet 4.6: ~$24
- 15% on Opus 4.6: ~$24
- **Total: ~$48** vs uniform-Sonnet $96 → **50% savings**

The skill's single-model cost column doesn't show this — it just reports the upper bound. Always compute the mix separately and present both numbers.

**Automated mix calculation:** Use the bundled script `scripts/optimize-model-mix.py` for exact per-category splits:

```bash
# Default balanced mix
python3 scripts/optimize-model-mix.py --loc 26150

# Quality tier variants
python3 scripts/optimize-model-mix.py --loc 5000 --quality budget      # 60-80% savings
python3 scripts/optimize-model-mix.py --loc 50000 --quality premium    # Opus-heavy, 20-30% savings
python3 scripts/optimize-model-mix.py --loc 2000 --quality ultra-budget # 80%+ savings

# Refresh prices from llmgateway GitHub (monthly)
python3 scripts/optimize-model-mix.py --fetch --loc 10000
```

The script caches prices in `/tmp/model_prices.json` (refresh with `--fetch`). It reads from the same llmgateway aggregator referenced in the Top Market Models section, so the numbers stay in sync.

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
- [ ] Use selective context — only load files relevant to current task
- [ ] Periodically summarize decisions and start clean chats
- [ ] When debugging, paste only relevant error lines (not full stack traces)
- [ ] Break large files (600+ lines) before asking AI to modify them
- [ ] For Rust/MASM: provide type signatures upfront to reduce reasoning tokens
- [ ] For boilerplate-heavy frameworks (SeaORM, Prisma): create "Type Summaries" instead of sending full generated code
- [ ] Start clean sessions every 2-3 days to reset context accumulation
```

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
   - **Polish-loop heavy** — review-fix-fix cycles (eapbuild pattern) → 1.5x

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
   dev_hours_throughput = net_hand_authored_LOC / 820           # or the character-matched LOC/h
   ```
   - Within 1.5x → quote the range.
   - 1.5–2.5x apart → take the higher.
   - >2.5x apart → complexity or rhythm is wrong; redo sub-steps 2 and 4.

   Then apply the **AI-assistance factor** (mature ≥100k-LOC repo = 1.19x *slower*, per the METR RCT — do not discount) and the **team-size multiplier** if the project is not solo. Add the billing line **only** if the user gave an hourly rate.

8. **Sanity check** against reference projects (table in Time section above). If estimate is >2x off from anchor, re-check steps 3-5. Cross-check hours against the measured set: a solo full-time month of committed work ≈ **110–140 h** (22 active days × 5.5), and the largest calibration repo (astral_project, 185k hand LOC) cost **275 h**. An estimate claiming 500 h for a 50k-LOC app is wrong.

**Output to `{slug}-estimative.md`** (extends the template):

```markdown
## Time & Wall-Clock Estimate

| Feature | Complexity | Span (days) | Net hand LOC est |
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
- **Throughput estimator:** {net hand LOC} / {LOC-per-h for character} = **{N} h**
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
```

---

## File Naming Convention

Always use the user-provided slug:
- `{slug}-paths.md`
- `{slug}-plan.md`
- `{slug}-steps.md`
- `{slug}-estimative.md`

## Progress Tracking

After each step, update `{slug}-steps.md` with:
- Status (pending/in_progress/done)
- What was found
- Any blockers
