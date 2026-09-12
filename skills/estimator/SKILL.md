---
name: estimator
description: Estimate a project's token cost, USD, dev-hours and calendar time from a prompt or repo, calibrated against measured git history and Claude Code session usage. Use for "Estimate" / "How long will this take" / "how much will this cost". Saves {slug}-plan.md, {slug}-steps.md, {slug}-estimative.md.
---

Throughout this file, `<skill>` means the directory holding this SKILL.md (e.g.
`~/.claude/skills/estimator`) — every `scripts/...` invocation below runs from
there, not from the target project's working directory.

## Prerequisites

Initialize RTK in the target project before analysis, so command output stays
token-optimized:

```bash
# In the project directory you will work on:
rtk init
```

## Output Files

All results are saved to files with the given slug:

- `{slug}-plan.md` — the analysis plan and approach
- `{slug}-steps.md` — step-by-step progress log
- `{slug}-estimative.md` — estimation results

A re-run **overwrites** all three. The previous generation is rotated to
`{slug}-*.prev.md` (one level only) so the new estimate can be diffed against it —
see Step 0.

## Token Estimation — Turn-Based (MEASURED)

**The unit of cost is one assistant turn, never a line of code.** What gets billed
is conversation context re-sent on every turn, not the surviving code — a 200-line
file discussed across 40 turns bills ~40 times. Measured over 15 real Claude Code
histories (16k+ turns, 3.2B billed tokens; reproduce with `python3
<skill>/scripts/session-tokens.py --constants`). **LOC is a proxy**: it locates the
band below and cross-checks the turn count — turns are the input, LOC never
multiplies directly into a project total.

**Tight constants (spread < 7× — safe as anchors):**

| Per assistant turn | min | **median** | max | spread |
|--------------------|-----|------------|-----|--------|
| Total billed tokens | 44 k | **135 k** | 282 k | 6.4× |
| Output tokens | 290 | **1,000** | 1,840 | 6.3× |
| USD, premium tier, cache-aware | $0.04 | **$0.13** | $0.20 | 5.3× |
| Cache-read share of input | 84 % | **97 %** | 98 % | — |

Turns/hour and tokens/hour ratios spread >20× (heavy sub-agent and background usage
decouples turn count from attended hours) — too noisy to anchor on directly.
Estimate turns **per deliverable**, never per hour.

### Cache pricing is not optional (cache-aware)

97 % of billed input is a cache read, priced at 0.10× base input. Ignoring the
cache over-prices the input leg by roughly 10×. Split every input estimate:

```
input_tokens       = turns × 134,000
cache_read_tokens  = input_tokens × 0.97   →  price × 0.10
cache_write_tokens = input_tokens × 0.03   →  price × 1.25
output_tokens      = turns × 1,000         →  price × 1.00
```

Bill extended-thinking tokens as output; raise `output_tokens/turn` toward the 1,840
ceiling for reasoning-heavy work instead of adding a separate reasoning leg.
Everywhere else this document says *cache-aware*, it means this split.

### Estimate turns per deliverable

Derive turns from the deliverable list, then cross-check against the added-LOC/turn
band (median 22, band 9–178):

| Feature tier | Typical net LOC | Turns (median rate) | Turns (band) |
|--------------|-----------------|---------------------|--------------|
| trivial (rename, 1-line fix) | ~30 | 2 | 1–4 |
| simple (isolated util, config) | ~465 | 21 | 3–50 |
| medium (single module, CRUD, fix-loop) | ~1,500 | 68 | 8–170 |
| complex (multi-module, design decisions) | ~5,000 | 227 | 30–560 |
| critical (architecture, RAG, full-stack) | ~12,000 | 545 | 70–1,300 |

Shapes that don't map cleanly to a tier by LOC alone: full-stack feature
(frontend+backend+tests) ~2,500 net LOC; infra/devops setup ~800 net LOC — place
each in the nearest tier by turns, not by re-deriving from LOC. No existing repo to
scan (greenfield/spec-only)? Derive these same LOC anchors from the spec's feature
descriptions instead of measuring, and widen every band by ±30%.

Add non-feature turns explicitly — often 20–30 % of the total:

| Activity | Turns |
|----------|-------|
| Planning, architecture, spec | 20–80 |
| Test authoring and green-loop | 30 % of feature turns |
| Debug / build-fix cycles | 25 % of feature turns |
| Review, refactor, polish loops | 15 % of feature turns |
| Documentation, CI/CD, deploy | 15–60 |

### Price it

```bash
python3 <skill>/scripts/estimate-cost.py --turns N --net-loc N ...
```

The formula it implements: `tokens = turns × 135,000` (band 44k–282k),
`cost = turns × $0.13` (band $0.04–$0.20). Always quote the band, never the point.

The script also runs the four sanity gates (USD/turn, tokens/turn, tokens/added
LOC, output share) and the direct-anchor cross-check (`turns × $0.13` must land
within 20% of the cache-aware total) — a `[FAIL]` row or a cross-check warning means
the turn count or an input is wrong; fix it, do not fudge the price.

LOC → tokens sizes **one file** in context, not a project total (proxy, see above):

| Language / Type | Tokens/Line | Dense* |
|-----------------|-------------|--------|
| Python | ~10 | ~12 |
| JS / TS (typed) | ~7–10 | ~10–13 |
| Rust (simple / macro-heavy) | ~10–12 / ~14–16 | ~14 / ~18 |
| Solidity | ~12–14 | ~16 |
| Mixed codebase (avg) | **~10** | ~14 |

\* macros, generics, complex types, derive attributes, interface types, runes.
Each file loaded into context also costs ~150 tokens of path/separator metadata.

### Complexity: raise turns, not multipliers

Complexity moves the turn count and the output-per-turn figure — it does not get
its own price multiplier, both are already in the tables above:

| Complexity | Turn adjustment | Output/turn |
|------------|-----------------|--------------|
| Simple | ×1.0 | ~600 |
| Medium | ×1.3 | ~1,000 |
| Complex | ×1.8 | ~1,400 |
| Critical (auditable) | ×2.5 | ~1,800 |

## Model Pricing (USD per 1M tokens) — Anthropic

Cache write is 1.25× input; cache read is 0.10× input. Extended thinking bills as
output.

| Model | Input | Cache write | Cache read | Output | Context |
|-------|-------|-------------|------------|--------|---------|
| Opus 5 / Opus 4.6 | $5.00 | $6.25 | $0.50 | $25.00 | 200k (1M variant) |
| Fable 5 | $10.00 | $12.50 | $1.00 | $50.00 | 1M |
| Sonnet 5 | $2.00 | $2.50 | $0.20 | $10.00 | 200k |
| Sonnet 4.6 | $3.00 | $3.75 | $0.30 | $15.00 | 200k |
| Haiku 4.5 | $1.00 | $1.25 | $0.10 | $5.00 | 200k |

Effective blended rate at 97% cache-read share: a premium-tier turn costs ~$0.13,
not the ~$0.70 a naive full-price calculation produces. Providers without prompt
caching price every token at full input rate — 8–10× more for the same workload.
For every other provider's current price, or to mix models by task type for
savings, see [`reference/pricing.md`](reference/pricing.md) — it points at
`<skill>/scripts/optimize-model-mix.py`, which fetches live prices rather than a
table that goes stale in this document.

The **Project Size Reference Table** (turns/LOC/cost bands by project shape,
used by Step 3's reclassify check) and its observed whole-repo anchors are in
[`reference/calibration.md`](reference/calibration.md#project-size-reference-table).

**Blockchain/smart-contract project?** Security audits are mandatory and scale with
size — read [`reference/smart-contracts.md`](reference/smart-contracts.md) and flag
audit requirements in the output. AI pre-audit does not replace a formal audit.

## Workflow

### Step 0 — Get the slug and reset previous output

Ask the user for a project slug (e.g., "my-api-project", "react-dashboard").

**A re-run overwrites the previous estimate — it never appends.** Before writing
anything:

```bash
for f in {slug}-plan.md {slug}-steps.md {slug}-estimative.md; do
  [ -f "$f" ] && mv -f "$f" "${f%.md}.prev.md"
done
```

This keeps exactly one previous generation as `{slug}-*.prev.md`, and guarantees
stale sections from an older run never leak into the new one. If
`{slug}-estimative.prev.md` exists, add a **Revision History** row to the new
estimative recording what changed and why.

Initialize `{slug}-steps.md`:
````markdown
# Steps: {slug}

## Step 1: Analyze Prompt
- Status: pending|done
- Notes:

## Step 2: Cost Estimate
- Status: pending|done
- Notes:

## Step 3: Wall-Clock & Dev-Hours Calibration
- Status: pending|done
- Notes:
````

Flip a step's `Status` to `done` only once the artefact section its own criterion
names below exists and is non-empty — a self-declared `done` with an empty section
is not done.

### Step 1 — Analyze Prompt

Understand the user's idea/prompt: goal, project type, technologies/languages,
features, complexity level (simple/medium/complex).

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

### Architecture Decisions
- Decision 1: [trade-offs, implications]

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

**Done when** all six Prompt Analysis fields carry a non-empty value AND the
Research Turn Estimate subtotal has its three component counts filled in. An empty
or TBD field is not done. Update `{slug}-steps.md`.

### Step 2 — Cost Estimate

Create `{slug}-estimative.md`, starting with `## STATUS: draft (Step 3 pending)` on
its first line — remove that line only after Step 3 runs; a cost-only estimate
without wall-clock time doesn't tell the user when it ships or how many hours it
bills.

````markdown
# Estimation: {slug}

## STATUS: draft (Step 3 pending)

## Project Summary
- Goal: {description}
- Type: {project-type}
- Complexity: simple|medium|complex

## Deliverable Breakdown

| Deliverable | Tier | Net LOC (est) | Turns | Confidence |
|-------------|------|---------------|-------|------------|
| {feature 1} | medium | 1,500 | 68 | med |
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

## Token & Cost Estimate

Paste the output of `<skill>/scripts/estimate-cost.py --turns {base} --net-loc {n}` here verbatim,
including its Sanity Gates block and the direct-anchor cross-check line. Any
`[FAIL]` gate or cross-check warning must be resolved (fix the turn count or LOC
input) before this section counts as done.

## Cost by Model (same turn count)

Re-run the script with `--input-price`/`--output-price` for Sonnet 5 ($2/$10) and
Haiku 4.5 ($1/$5) if a cheaper quote is wanted; list each total.
**Recommended model:** {model} — {reason}. **Budget alternative:** {model} — {reason}.

## Smart Contract Audit (if applicable, see reference/smart-contracts.md)

| Item | Estimated Cost | Notes |
|------|---------------|-------|
| AI pre-audit | {n} turns (~${x}) | Static analysis, invariants, gas review |
| Formal audit (external) | {real quote required} | Not estimated here — see reference file |
````

**Done when** every `{n}`/`${x}` placeholder above is filled and the pasted script
output shows no `[FAIL]` gate. Update `{slug}-steps.md`.

### Step 3 — Wall-Clock & Dev-Hours Calibration

Converts the cost estimate into calendar time and dev-hours. Full calibration
tables and their provenance are in
[`reference/calibration.md`](reference/calibration.md); this procedure states only
the formula and the judgement calls.

**Rhythm is calendar-only** — the rhythm multiplier applies to calendar days, never
to hours (h/active day is nearly flat across rhythms; applying it twice
double-counts).

1. **Decompose into unit features** — atomic features one commit-batch could
   complete, same decomposition as the Deliverable Breakdown table in Step 2 but
   finer-grained (e.g. "Auth with Google OAuth" is one feature, not "auth").
2. **Classify each feature's complexity**: trivial / simple / medium / complex /
   critical (same tiers as §Estimate turns per deliverable).
3. **Apply the span table** — median days, first→last commit: trivial 1d, simple
   1d, medium 2d, complex 8d, critical 28d (full spread in
   [`reference/calibration.md`](reference/calibration.md#feature-span-observed-distribution-across-the-6-calibration-repos)).
4. **Identify rhythm profile** and its calendar multiplier: sustained burn (daily
   commits) 1.0x, sprint-and-rest (3–7d bursts, then a gap) 1.4x, build+tail (heavy
   phase + 1–2 commits/month) 1.6x, burst+gap+consolidation (month-long gaps
   between phases) 1.8x, polish-loop heavy (>10% sub-200-LOC fix/chore commits)
   1.5x.
5. **Count polish loops** — % of commits that are sub-200-LOC `fix:`/`style:`/
   `chore:`/`docs:`/no-behavior-change `refactor:`: <5% → +0%; 5–10% → +20%;
   10–20% → +50%; >20% → +100% (and reconsider scope — a review-fix loop this size
   isn't converging).
6. **Compute day totals**:
   ```
   project_calendar_days = Σ(feature_span) × rhythm_multiplier × (1 + polish_loop_rate × 0.5)  # calendar-only
   project_working_days  = project_calendar_days × (active_days_per_week / 7)   # default 1.5/7
   ```
7. **Compute dev-hours** — two independent estimators, always both, then
   reconcile:
   - **Measure first.** If a comparable repo exists (same team/stack/prior
     version), run `python3 <skill>/scripts/git-hours.py --repo <path>` and use its
     measured `h/day` and `LOC/h` in place of the defaults below. If none exists,
     write the verbatim sentence "no comparable repo: searched \<paths listed\>" —
     do not skip this silently.
     ```
     dev_hours_cadence    = project_working_days × 5.5      # default, band 5.0-7.0 h/active day
     dev_hours_throughput = net_committed_LOC / 820         # default, band 300-1,300 LOC/h
     ```
   - **Reconcile:** within 1.5x → quote the range; 1.5–2.5x apart → take the
     higher (under-estimation is the observed failure mode); >2.5x apart → wrong
     tier or rhythm, re-do sub-steps 3.2 (complexity) and 3.4 (rhythm).
   - Apply the **AI-assistance factor** — greenfield/scaffolding 0.5–0.7x, new
     feature in <100k-LOC repo 0.85x, mature ≥100k-LOC repo dev knows well **1.19x**
     (a measured slowdown, not a discount — METR RCT), unfamiliar codebase 0.8x —
     and the **team-size multiplier** if not solo (2 devs: calendar ÷1.6, hours
     ×1.15; 3: ÷2.1, ×1.30; 4+: ÷2.5, ×1.50). Add a billing line only if the user
     gave an hourly rate.

   Hours, tokens and calendar days are **orthogonal** — a project can be
   token-cheap and hour-expensive, or the reverse. Never derive one from another.

8. **Sanity check** against the anchors in
   [`reference/calibration.md`](reference/calibration.md#sanity-check-anchors-reference-projects).
   If your estimate diverges >2x, re-check whether polish loops were
   double-counted or the rhythm multiplier was skipped. This is the guard against
   **under-classification** — the single most common estimation error, where a
   prompt framed as "Medium MVP" hides Large-app scope. After computing total LOC,
   compare it against the Project Size Reference Table above; if it lands 2x or
   more above the band implied by the user's framing, flag it explicitly:

   ````markdown
   ## ⚠️ Reclassify Check
   - Prompt framing: "Medium MVP" → expected band: 5–15k LOC / 150–700 turns / $20–$91
   - Computed: ~26k LOC / ~1,100 turns / ~$143
   - Computed is 1.7x above the implied band → **reclassify as Large app**
   ````

Remove the `## STATUS: draft` line from `{slug}-estimative.md` and append:

````markdown
## Time & Wall-Clock Estimate

| Feature | Complexity | Span (days) | Net LOC est |
|---------|-----------|-------------|-------------|
| {feature 1} | medium | 2 | 1,200 |

- **Rhythm profile:** {profile} · **multiplier:** {1.0-1.8x}
- **Polish-loop rate:** {0-100%} → adjustment {0-100%}
- **Calendar days:** {N} · **Working days:** {N}

## Dev-Hours Estimate
- **Cadence:** {working_days} × {h/day} = **{N} h**
- **Throughput:** {net LOC} / {LOC/h} = **{N} h**
- **Reconciled:** {lo}–{hi} h ({quote range | took higher | redid classification})
- **AI-assistance factor:** {0.5-1.19}x ({context}) · **Team:** {N}
- **➡️ Dev-hours (final):** **{lo}–{hi} h**
- **Basis:** {measured via git-hours.py on <repo> | derived from calibration tables}

### Total Cost (only if hourly rate provided)
- Dev cost: {hours} h × ${rate}/h = **${N}**
- AI token cost: **${N}**
- **Total: ${N}**
````

**Done when** every placeholder above is filled, the Reclassify Check ran (even if
it found nothing to flag), and the `## STATUS: draft` line is gone. Update
`{slug}-steps.md`.

## File Naming Convention

- `{slug}-plan.md`, `{slug}-steps.md`, `{slug}-estimative.md` — always the
  user-provided slug. A re-run replaces all three; Step 0 rotates the previous
  generation to `{slug}-*.prev.md` (one level of history). Keep exactly one current
  estimate and one previous — never append to an old file, never keep timestamped
  variants.
