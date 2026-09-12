# Model-mix strategy (cost optimization)

Consult this file only when the user wants a cheaper multi-model mix instead of a
single-model quote. Real savings come from mixing models by task type, not from
picking one cheaper model for everything.

| Task type | Recommended model | Why |
|-----------|-------------------|-----|
| CRUD, migrations, scaffolding, configs | DeepSeek V3.2 or Gemini 2.5 Flash Lite | Mechanical patterns, <$1/M output, no reasoning needed |
| Bug fixes, refactors, polish loops | MiniMax M2.5 or Sonnet 5 | Need some reasoning, balance cost/quality |
| Architecture decisions, novel patterns | Current Sonnet- or Opus-tier Claude | Reasoning matters here |
| Smart contracts, security-critical | Current Opus-tier Claude only | Cost is not the constraint |

**Rule of thumb for greenfield SaaS:** ~60% CRUD/scaffolding (cheap model), ~25%
refactor/polish (mid model), ~15% architectural (premium model). Splitting this way
cuts total cost 50–70% vs uniform-Sonnet — but only if the cheap tier does not
increase turn count. State the turn-count assumption next to any mix-savings claim.

**Compute the mix with the bundled script** — it fetches live prices, so it is the
one source of truth for third-party model pricing (this file carries no price
table):

```bash
python3 <skill>/scripts/optimize-model-mix.py --turns 1100                        # default balanced mix
python3 <skill>/scripts/optimize-model-mix.py --turns 230 --quality budget         # 60-80% savings
python3 <skill>/scripts/optimize-model-mix.py --turns 2000 --quality premium       # Opus-heavy, 20-30% savings
python3 <skill>/scripts/optimize-model-mix.py --turns 90 --quality ultra-budget    # 80%+ savings
python3 <skill>/scripts/optimize-model-mix.py --fetch --turns 400                  # refresh prices from llmgateway (monthly)
```

Report both the single-model upper bound (`--quality premium`, all-Opus) and the
mix. The script uses the same cache-aware turn model as `estimate-cost.py`.

## When to override the mix

- **Single-agent workflow** (one model for everything): drop the mix, pick the
  cheapest tier that meets quality needs.
- **Latency-critical** (interactive coding, real-time responses): premium tier pays
  for itself with fewer iterations.
- **Security/financial code** (smart contracts, payments): critical = 100% Opus
  regardless of cost.
- **Exploration/prototyping**: start at ultra-budget, scale up if quality issues
  surface.
