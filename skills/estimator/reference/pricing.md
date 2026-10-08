# Model-mix strategy (cost optimization)

Use this reference for provider alternatives, single-model quotes, and multi-model
mixes. Price data comes from PPQ's public model catalog; the bundled script refreshes
it and uses published cache rates when available.

| Task type | Recommended model | Why |
|-----------|-------------------|-----|
| CRUD, migrations, scaffolding, configs | Tencent Hy3 or DeepSeek V4.1 Flash | Low-cost mechanical work |
| Bug fixes, refactors, polish loops | DeepSeek V4.1 Flash or Tencent Hy4 Preview | Mid-tier reasoning and code work |
| Architecture decisions, novel patterns | Kimi K3, Tencent Hy4 Preview, or current Claude | Compare quality needs and live price |
| Smart contracts, security-critical | Current Opus-tier Claude only | Cost is not the constraint |

**Rule of thumb for greenfield SaaS:** ~60% CRUD/scaffolding (cheap model), ~25%
refactor/polish (mid model), ~15% architectural (premium model). Splitting this way
cuts total cost 50–70% vs uniform-Sonnet — but only if the cheap tier does not
increase turn count. State the turn-count assumption next to any mix-savings claim.

**Refresh prices and compare a mix or a single model:**

```bash
python3 <skill>/scripts/optimize-model-mix.py --turns 1100                        # default balanced mix
python3 <skill>/scripts/optimize-model-mix.py --turns 230 --quality budget         # 60-80% savings
python3 <skill>/scripts/optimize-model-mix.py --turns 2000 --quality premium       # Opus-heavy, 20-30% savings
python3 <skill>/scripts/optimize-model-mix.py --turns 90 --quality ultra-budget    # 80%+ savings
python3 <skill>/scripts/optimize-model-mix.py --fetch --turns 400                  # refresh prices from PPQ
python3 <skill>/scripts/optimize-model-mix.py --turns 400 --model tencent/hy4-preview
python3 <skill>/scripts/optimize-model-mix.py --fetch --scenario-turns 18,32,54 --model deepseek/deepseek-v4.1-flash --budget-model
python3 <skill>/scripts/optimize-model-mix.py --list-models --provider tencent
```

Report the selected provider/model and price-catalog timestamp. Workload tokens
remain calibrated from Claude Code histories, while model rates come from PPQ;
label totals as PPQ pricing because provider rates and routing can vary. The 97%
cache-read share is a workload estimate. `--list-models` prints current IDs and
`--model` prices all turns on a selected model. `--scenario-turns LOW,BASE,HIGH`
prints alternative scenario costs; `--budget-model` adds the independent high +
20% ceiling and base × 1.5 retry sensitivity.

## When to override the mix

- **Single-agent workflow** (one model for everything): drop the mix, pick the
  cheapest tier that meets quality needs.
- **Latency-critical** (interactive coding, real-time responses): premium tier pays
  for itself with fewer iterations.
- **Security/financial code** (smart contracts, payments): critical = 100% Opus
  regardless of cost.
- **Exploration/prototyping**: start at ultra-budget, scale up if quality issues
  surface.
