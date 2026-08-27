#!/usr/bin/env python3
"""
optimize-model-mix.py — Calculate the cheapest multi-model mix for a project
estimation, given total LOC and a quality threshold.

Uses llmgateway.io prices (cached in /tmp/model_prices.json) and the project's
LOC estimation. Outputs per-task-type model assignments and total cost.

Usage:
    python3 optimize-model-mix.py --loc 26150
    python3 optimize-model-mix.py --loc 5000 --quality budget
    python3 optimize-model-mix.py --loc 100000 --quality premium
    python3 optimize-model-mix.py --fetch    # refresh prices first

Quality tiers:
    - ultra-budget: 100% mechanical (Mistral Small, Gemini Flash Lite)
    - budget:       60% mechanical, 25% mid, 15% premium
    - balanced:     default — 40/40/20 mechanical/mid/premium
    - premium:      30% mechanical, 40% mid, 30% premium (Opus-heavy)

Per the skill's Model-Mix Strategy: splitting by task type typically cuts
cost by 50-70% vs uniform-Sonnet without measurable quality loss.
"""

import argparse
import json
import os
import sys
import urllib.request
from typing import Dict, List, Tuple

PRICES_CACHE = "/tmp/model_prices.json"

# Default model picks per task type × quality tier.
# "mechanical" = CRUD, migrations, configs (low reasoning needed)
# "mid" = refactor, polish, bug fixes (some reasoning)
# "premium" = architecture, novel patterns (high reasoning)
# "critical" = security, smart contracts (Opus only)

DEFAULT_MODELS = {
    "ultra-budget": {
        "mechanical": ["gemini/gemini-2.5-flash-lite", "mistral/mistral-small-2506"],
        "mid":        ["gemini/gemini-2.5-flash-lite", "alibaba/qwen-flash"],
        "premium":    ["deepseek/deepseek-v3.2", "alibaba/qwen-plus-latest"],
        "critical":   ["deepseek/deepseek-r1-0528"],
    },
    "budget": {
        "mechanical": ["mistral/mistral-small-2506", "gemini/gemini-2.5-flash-lite", "alibaba/qwen-flash"],
        "mid":        ["alibaba/qwen-plus-latest", "mistral/mistral-large-2512", "minimax/minimax-m2.5"],
        "premium":    ["anthropic/claude-sonnet-4-6", "deepseek/deepseek-v3.2"],
        "critical":   ["anthropic/claude-sonnet-4-6"],
    },
    "balanced": {
        "mechanical": ["mistral/mistral-small-2506", "alibaba/qwen-flash"],
        "mid":        ["anthropic/claude-sonnet-5", "alibaba/qwen-plus-latest", "minimax/minimax-m2.5"],
        "premium":    ["anthropic/claude-sonnet-5", "anthropic/claude-opus-4-6"],
        "critical":   ["anthropic/claude-opus-4-6"],
    },
    "premium": {
        "mechanical": ["mistral/mistral-large-2512", "anthropic/claude-sonnet-5"],
        "mid":        ["anthropic/claude-sonnet-5", "anthropic/claude-opus-4-6"],
        "premium":    ["anthropic/claude-opus-4-6", "anthropic/claude-opus-5"],
        "critical":   ["anthropic/claude-opus-4-6"],
    },
}

# Task distribution by quality tier (% of total tokens per category)
TASK_DISTRIBUTION = {
    "ultra-budget": {"mechanical": 0.70, "mid": 0.20, "premium": 0.10, "critical": 0.00},
    "budget":       {"mechanical": 0.60, "mid": 0.25, "premium": 0.15, "critical": 0.00},
    "balanced":     {"mechanical": 0.40, "mid": 0.40, "premium": 0.18, "critical": 0.02},
    "premium":      {"mechanical": 0.30, "mid": 0.40, "premium": 0.25, "critical": 0.05},
}


def fetch_prices() -> Dict:
    """Fetch all provider model files from llmgateway GitHub and parse prices."""
    providers = ["anthropic", "openai", "google", "deepseek", "minimax", "zai",
                 "xai", "meta", "mistral", "alibaba"]
    flat = {}
    for prov in providers:
        url = f"https://raw.githubusercontent.com/theopenco/llmgateway/main/packages/models/src/models/{prov}.ts"
        try:
            content = urllib.request.urlopen(url, timeout=10).read().decode("utf-8")
        except Exception as e:
            print(f"WARN: failed to fetch {prov}: {e}", file=sys.stderr)
            continue
        # Parse each model block
        import re
        pattern = re.compile(
            r'\n\t\{\n\t\tid:\s*"([^"]+)",.*?\n\t\tname:\s*"([^"]+)".*?providers:\s*\[(.*?)\n\t\t\],',
            re.DOTALL
        )
        for m in pattern.finditer(content):
            m_id, name, providers_block = m.group(1), m.group(2), m.group(3)
            in_match = re.search(r'providerId:\s*"([^"]+)".*?inputPrice:\s*"([\d.eE+-]+)".*?outputPrice:\s*"([\d.eE+-]+)"', providers_block, re.DOTALL)
            if not in_match:
                continue
            inp = float(in_match.group(2)) * 1_000_000
            outp = float(in_match.group(3)) * 1_000_000
            key = f"{prov}/{m_id}"
            flat[key] = {
                "id": m_id, "name": name, "provider": prov,
                "input_per_M": round(inp, 4), "output_per_M": round(outp, 4)
            }
    return flat


def load_prices(force_refresh: bool = False) -> Dict:
    """Load prices from cache or fetch fresh."""
    if force_refresh or not os.path.exists(PRICES_CACHE):
        print(f"Fetching fresh prices from llmgateway GitHub...")
        prices = fetch_prices()
        with open(PRICES_CACHE, "w") as f:
            json.dump(prices, f, indent=2)
        print(f"  → {len(prices)} models cached to {PRICES_CACHE}")
        return prices
    with open(PRICES_CACHE) as f:
        return json.load(f)


def cost_estimate(loc: int, quality: str, prices: Dict, tokens_per_loc: int = 10) -> Dict:
    """
    Estimate total cost for a project of `loc` LOC at the given quality tier.

    Returns dict with:
        - per_task_type: list of (category, model, cost, share_pct)
        - total_cost: USD
        - baseline_cost: cost if all tokens went to Sonnet 4.6 (for comparison)
        - savings_vs_baseline: %
    """
    # Total tokens per the skill's 10x rule: code tokens × 10
    base_tokens = loc * tokens_per_loc
    total_tokens = base_tokens * 10  # 10x iceberg
    # Split into input (75%) and output (25%)
    input_tokens = total_tokens * 0.75
    output_tokens = total_tokens * 0.25

    distribution = TASK_DISTRIBUTION[quality]
    models_by_cat = DEFAULT_MODELS[quality]

    per_cat = []
    total_cost = 0.0

    for category, share in distribution.items():
        if share == 0:
            continue
        # Try each candidate model in priority order; pick the cheapest that exists
        candidates = models_by_cat[category]
        chosen = None
        for cand in candidates:
            if cand in prices:
                chosen = cand
                break
        if not chosen:
            print(f"WARN: no model found for category={category}, candidates={candidates}", file=sys.stderr)
            continue

        model = prices[chosen]
        cat_input = input_tokens * share
        cat_output = output_tokens * share
        cost = (cat_input * model["input_per_M"] + cat_output * model["output_per_M"]) / 1_000_000
        per_cat.append({
            "category": category,
            "model": chosen,
            "model_name": model["name"],
            "input_per_M": model["input_per_M"],
            "output_per_M": model["output_per_M"],
            "share_pct": round(share * 100, 1),
            "input_tokens": int(cat_input),
            "output_tokens": int(cat_output),
            "cost_usd": round(cost, 2),
        })
        total_cost += cost

    # Baseline: all tokens on Sonnet 4.6 (the skill's default reference)
    baseline = None
    if "anthropic/claude-sonnet-4-6" in prices:
        sonnet = prices["anthropic/claude-sonnet-4-6"]
        baseline = (input_tokens * sonnet["input_per_M"] + output_tokens * sonnet["output_per_M"]) / 1_000_000

    savings_pct = None
    if baseline:
        savings_pct = round((baseline - total_cost) / baseline * 100, 1)

    return {
        "loc": loc,
        "quality_tier": quality,
        "total_tokens": int(total_tokens),
        "per_task_type": per_cat,
        "total_cost_usd": round(total_cost, 2),
        "baseline_sonnet_4_6_usd": round(baseline, 2) if baseline else None,
        "savings_vs_sonnet_pct": savings_pct,
    }


def print_report(result: Dict):
    print(f"\n{'=' * 70}")
    print(f"MODEL-MIX COST OPTIMIZATION")
    print(f"{'=' * 70}")
    print(f"LOC:              {result['loc']:,}")
    print(f"Quality tier:     {result['quality_tier']}")
    print(f"Total tokens:     {result['total_tokens']:,} (10x LOC rule)")
    print()
    print(f"{'Category':<12} {'Model':<35} {'$/M in':>8} {'$/M out':>8} {'Share':>7} {'Cost':>8}")
    print("-" * 90)
    for cat in result["per_task_type"]:
        print(f"{cat['category']:<12} {cat['model']:<35} "
              f"${cat['input_per_M']:>6.3f} ${cat['output_per_M']:>6.3f} "
              f"{cat['share_pct']:>5.1f}% ${cat['cost_usd']:>6.2f}")
    print("-" * 90)
    print(f"{'TOTAL':<60} {'':>22} ${result['total_cost_usd']:>6.2f}")
    print()
    if result.get("baseline_sonnet_4_6_usd"):
        baseline = result["baseline_sonnet_4_6_usd"]
        savings = result["savings_vs_sonnet_pct"]
        print(f"Baseline (all Sonnet 4.6):   ${baseline:.2f}")
        print(f"Savings vs baseline:        {savings}%")
    print()


def main():
    parser = argparse.ArgumentParser(description="Optimize model mix for project estimation")
    parser.add_argument("--loc", type=int, help="Estimated total LOC of the project (must be > 0)")
    parser.add_argument("--quality", choices=["ultra-budget", "budget", "balanced", "premium"],
                        default="balanced", help="Quality tier (default: balanced)")
    parser.add_argument("--tokens-per-loc", type=int, default=10,
                        help="Tokens per LOC (default 10, use 14 for Rust/Solidity/complex TS)")
    parser.add_argument("--fetch", action="store_true", help="Force refresh prices from llmgateway")
    args = parser.parse_args()

    if args.loc is None or args.loc <= 0:
        parser.error("--loc must be a positive integer")

    prices = load_prices(force_refresh=args.fetch)
    result = cost_estimate(args.loc, args.quality, prices, args.tokens_per_loc)
    print_report(result)


if __name__ == "__main__":
    main()
