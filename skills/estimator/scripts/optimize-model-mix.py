#!/usr/bin/env python3
"""
optimize-model-mix.py — Calculate the cheapest multi-model mix for a project
estimation, given a turn count and a quality threshold.

Uses PPQ's public model prices (cached in /tmp/model_prices.json) and the skill's
cache-aware turn cost model. Outputs per-task-type model assignments and
total cost.

Turn model (see SKILL.md "Cache pricing is not optional" / "Cost Calculation
Formula"): each turn burns ~134,000 input tokens (97% cache read, 3% cache
write) and ~1,000 output tokens. Never estimate tokens from LOC directly —
LOC × tokens-per-line only describes source-file size, not project cost.

Usage:
    python3 optimize-model-mix.py --turns 227
    python3 optimize-model-mix.py --turns 68 --quality budget
    python3 optimize-model-mix.py --turns 545 --quality premium
    python3 optimize-model-mix.py --loc 5000          # deprecated bridge, warns on stderr
    python3 optimize-model-mix.py --fetch --turns 100 # refresh prices first
    python3 optimize-model-mix.py --turns 100 --model tencent/hy4-preview
    python3 optimize-model-mix.py --list-models --provider tencent

Quality tiers:
    - ultra-budget: 100% mechanical (Mistral Small, Gemini Flash Lite)
    - budget:       60% mechanical, 25% mid, 15% premium
    - balanced:     default — 40/40/20 mechanical/mid/premium
    - premium:      30% mechanical, 40% mid, 30% premium

Model prices are fetched from PPQ; workload token volume is calibrated from
Claude Code histories. Treat cross-provider costs as estimates, not measured usage.
"""

import argparse
from datetime import datetime, timezone
import json
import os
import sys
import urllib.request
from urllib.error import URLError

PRICES_CACHE = "/tmp/model_prices.json"

# Cache-aware turn cost model constants (SKILL.md "Cache pricing is not optional").
INPUT_TOKENS_PER_TURN = 134_000
CACHE_READ_SHARE = 0.97
CACHE_WRITE_SHARE = 0.03
OUTPUT_TOKENS_PER_TURN = 1_000

# ponytail: SKILL.md states no LOC-per-turn constant; measured tiers land ~22
# net LOC/turn, rounded up to 30 so the bridge under-counts rather than inflates.
# Used only to keep --loc usable while it's deprecated.
LOC_PER_TURN = 30

# Cache read/write price multipliers applied to base input price when a
# price source has no explicit cache fields (SKILL.md "Cost Calculation
# Formula" / "effective Claude rates" section).
CACHE_READ_PRICE_MULTIPLIER = 0.10
CACHE_WRITE_PRICE_MULTIPLIER = 1.25

# Claude-history reference anchor, not a cross-provider price assertion.
CROSS_CHECK_USD_PER_TURN = 0.13
CROSS_CHECK_TOLERANCE_PCT = 20.0

# Default model picks per task type × quality tier.
# "mechanical" = CRUD, migrations, configs (low reasoning needed)
# "mid" = refactor, polish, bug fixes (some reasoning)
# "premium" = architecture, novel patterns (high reasoning)
# "critical" = security, smart contracts (Opus only)

DEFAULT_MODELS = {
    "ultra-budget": {
        "mechanical": ["tencent/hy3", "deepseek/deepseek-v4.1-flash", "gemini/gemini-2.5-flash-lite", "mistral/mistral-small-2506"],
        "mid":        ["deepseek/deepseek-v4.1-flash", "tencent/hy3", "gemini/gemini-2.5-flash-lite", "alibaba/qwen-flash"],
        "premium":    ["tencent/hy4-preview", "moonshotai/kimi-k3", "deepseek/deepseek-v4.1-flash", "alibaba/qwen-plus-latest"],
        "critical":   ["deepseek/deepseek-r1-0528"],
    },
    "budget": {
        "mechanical": ["tencent/hy3", "deepseek/deepseek-v4.1-flash", "mistral/mistral-small-2506", "gemini/gemini-2.5-flash-lite", "alibaba/qwen-flash"],
        "mid":        ["deepseek/deepseek-v4.1-flash", "tencent/hy4-preview", "alibaba/qwen-plus-latest", "mistral/mistral-large-2512", "minimax/minimax-m2.5"],
        "premium":    ["moonshotai/kimi-k3", "tencent/hy4-preview", "anthropic/claude-sonnet-4-6", "deepseek/deepseek-v4.1-flash"],
        "critical":   ["anthropic/claude-sonnet-4-6"],
    },
    "balanced": {
        "mechanical": ["tencent/hy3", "deepseek/deepseek-v4.1-flash", "mistral/mistral-small-2506", "alibaba/qwen-flash"],
        "mid":        ["tencent/hy4-preview", "deepseek/deepseek-v4.1-flash", "anthropic/claude-sonnet-5", "minimax/minimax-m2.5"],
        "premium":    ["moonshotai/kimi-k3", "tencent/hy4-preview", "anthropic/claude-sonnet-5", "anthropic/claude-opus-5"],
        "critical":   ["anthropic/claude-opus-5"],
    },
    "premium": {
        "mechanical": ["mistral/mistral-large-2512", "anthropic/claude-sonnet-5"],
        "mid":        ["anthropic/claude-sonnet-5", "anthropic/claude-opus-5"],
        "premium":    ["anthropic/claude-opus-5"],
        "critical":   ["anthropic/claude-opus-5"],
    },
}

# Task distribution by quality tier (% of total tokens per category)
TASK_DISTRIBUTION = {
    "ultra-budget": {"mechanical": 0.70, "mid": 0.20, "premium": 0.10, "critical": 0.00},
    "budget":       {"mechanical": 0.60, "mid": 0.25, "premium": 0.15, "critical": 0.00},
    "balanced":     {"mechanical": 0.40, "mid": 0.40, "premium": 0.18, "critical": 0.02},
    "premium":      {"mechanical": 0.30, "mid": 0.40, "premium": 0.25, "critical": 0.05},
}


def _fetch_prices_legacy() -> dict:
    """Legacy llmgateway parser kept for reference; current pricing uses PPQ."""
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


def fetch_prices() -> dict:
    """Fetch PPQ's public catalog with provider-specific cache-token rates."""
    try:
        with urllib.request.urlopen("https://api.ppq.ai/v1/models", timeout=20) as response:
            catalog = json.load(response)
    except (URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"ERROR: could not fetch PPQ model catalog: {exc}", file=sys.stderr)
        return {}
    prices = {}
    for item in catalog.get("data", []):
        pricing = item.get("pricing", {})
        if item.get("type") != "chat" or pricing.get("type") != "per_token":
            continue
        input_price = pricing.get("input_per_1M_tokens")
        output_price = pricing.get("output_per_1M_tokens")
        if input_price is None or output_price is None:
            continue
        model_id = item["id"]
        prices[model_id] = {
            "id": model_id, "name": item.get("name", model_id),
            "provider": item.get("owned_by", "unknown"),
            "input_per_M": float(input_price), "output_per_M": float(output_price),
        }
        for source, target in (("cache_read_per_1M_tokens", "cache_read_per_M"),
                               ("cache_write_per_1M_tokens", "cache_write_per_M")):
            if pricing.get(source) is not None:
                prices[model_id][target] = float(pricing[source])
    return prices


def load_prices(force_refresh: bool = False) -> dict:
    """Load prices from cache or fetch fresh."""
    required = {"moonshotai/kimi-k3", "tencent/hy4-preview", "deepseek/deepseek-v4.1-flash", "tencent/hy3"}
    cached = {}
    if os.path.exists(PRICES_CACHE) and not force_refresh:
        with open(PRICES_CACHE) as f:
            cached = json.load(f)
    if force_refresh or not required.issubset(cached):
        print("Fetching fresh prices from PPQ...")
        prices = fetch_prices()
        if prices:
            with open(PRICES_CACHE, "w") as f:
                json.dump(prices, f, indent=2)
        print(f"  → {len(prices)} models cached to {PRICES_CACHE}")
        return prices or cached
    return cached


def _pick_model(candidates: list, prices: dict) -> str | None:
    """Pick the first candidate model (priority order) that has known prices."""
    for cand in candidates:
        if cand in prices:
            return cand
    return None


def _cache_prices(model: dict) -> tuple[float, float]:
    """
    Return (cache_read_price, cache_write_price) per 1M tokens.

    Uses the price source's explicit cache fields when present, else derives
    them from the base input price via the SKILL.md multipliers (0.10x read,
    1.25x write).
    """
    input_price = model["input_per_M"]
    cache_read = model.get("cache_read_per_M", input_price * CACHE_READ_PRICE_MULTIPLIER)
    cache_write = model.get("cache_write_per_M", input_price * CACHE_WRITE_PRICE_MULTIPLIER)
    return cache_read, cache_write


def _turn_cost(turns: float, share: float, model: dict) -> float:
    """Cache-aware cost, in USD, for `share` of `turns` turns on `model`."""
    cache_read_price, cache_write_price = _cache_prices(model)
    input_tokens = INPUT_TOKENS_PER_TURN * turns * share
    output_tokens = OUTPUT_TOKENS_PER_TURN * turns * share
    cache_read_tokens = input_tokens * CACHE_READ_SHARE
    cache_write_tokens = input_tokens * CACHE_WRITE_SHARE
    return (
        cache_read_tokens * cache_read_price
        + cache_write_tokens * cache_write_price
        + output_tokens * model["output_per_M"]
    ) / 1_000_000


def _baseline_model_key(prices: dict) -> str | None:
    """Prefer Sonnet 5 as the baseline reference; fall back to Sonnet 4.6."""
    if "anthropic/claude-sonnet-5" in prices:
        return "anthropic/claude-sonnet-5"
    if "anthropic/claude-sonnet-4-6" in prices:
        return "anthropic/claude-sonnet-4-6"
    return None


def _cost_per_category(turns: int, quality: str, prices: dict) -> tuple[list, float]:
    """Build the per-task-type cost breakdown and running total."""
    distribution = TASK_DISTRIBUTION[quality]
    models_by_cat = DEFAULT_MODELS[quality]

    per_cat = []
    total_cost = 0.0
    for category, share in distribution.items():
        if share == 0:
            continue
        candidates = models_by_cat[category]
        chosen = _pick_model(candidates, prices)
        if not chosen:
            print(f"WARN: no model found for category={category}, candidates={candidates}", file=sys.stderr)
            continue

        model = prices[chosen]
        cost = _turn_cost(turns, share, model)
        per_cat.append({
            "category": category,
            "model": chosen,
            "model_name": model["name"],
            "input_per_M": model["input_per_M"],
            "output_per_M": model["output_per_M"],
            "share_pct": round(share * 100, 1),
            "cost_usd": round(cost, 2),
        })
        total_cost += cost
    return per_cat, total_cost


def cost_estimate(turns: int, quality: str, prices: dict) -> dict:
    """
    Estimate total cost for `turns` turns at the given quality tier, using the
    cache-aware turn model (SKILL.md "Cost Calculation Formula").

    Returns dict with per-task-type breakdown, total cost, baseline
    comparison, and a cross-check against the turns × $0.13 anchor.
    """
    per_cat, total_cost = _cost_per_category(turns, quality, prices)

    baseline_model_key = _baseline_model_key(prices)
    baseline = None
    if baseline_model_key:
        baseline = _turn_cost(turns, 1.0, prices[baseline_model_key])

    savings_pct = None
    if baseline:
        savings_pct = round((baseline - total_cost) / baseline * 100, 1)

    return {
        "turns": turns,
        "quality_tier": quality,
        "total_tokens": int((INPUT_TOKENS_PER_TURN + OUTPUT_TOKENS_PER_TURN) * turns),
        "per_task_type": per_cat,
        "total_cost_usd": round(total_cost, 2),
        "baseline_usd": round(baseline, 2) if baseline else None,
        "baseline_model": baseline_model_key,
        "savings_vs_baseline_pct": savings_pct,
        "cross_check_usd": round(turns * CROSS_CHECK_USD_PER_TURN, 2),
        "premium_single_usd": _premium_single_cost(turns, prices),
    }


def _premium_single_cost(turns: int, prices: dict) -> float | None:
    """All turns on the current Opus-tier model — the shape the $0.13/turn anchor was measured on."""
    for key in ("anthropic/claude-opus-5", "anthropic/claude-opus-4-6"):
        if key in prices:
            return round(_turn_cost(turns, 1.0, prices[key]), 2)
    return None


def _print_cross_check_warning(result: dict) -> None:
    """Warn when the single-Opus price drifts >20% from the turns × $0.13 anchor (pricing sanity, not mix)."""
    cross_check = result["cross_check_usd"]
    total = result.get("premium_single_usd")
    if not cross_check or total is None:
        return
    drift_pct = abs(total - cross_check) / cross_check * 100
    if drift_pct > CROSS_CHECK_TOLERANCE_PCT:
        print(
            f"WARN: all-Opus price ${total:.2f} diverges {drift_pct:.1f}% from the turns × $0.13 "
            f"cross-check (${cross_check:.2f}) — cache-read share or pricing may be wrong",
            file=sys.stderr,
        )


def print_report(result: dict) -> None:
    print(f"\n{'=' * 70}")
    print("MODEL-MIX COST OPTIMIZATION")
    print(f"{'=' * 70}")
    print(f"Turns:            {result['turns']:,}")
    print(f"Quality tier:     {result['quality_tier']}")
    print(f"Total tokens:     {result['total_tokens']:,} (cache-aware turn model)")
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
    if result.get("baseline_usd"):
        print(f"Baseline (all {result['baseline_model']}):   ${result['baseline_usd']:.2f}")
        print(f"Savings vs baseline:        {result['savings_vs_baseline_pct']}%")
    if result.get("premium_single_usd") is not None:
        print(f"All-Opus upper bound:       ${result['premium_single_usd']:.2f}")
    print(f"Anchor (turns × $0.13, all-Opus): ${result['cross_check_usd']:.2f}")
    print()
    _print_cross_check_warning(result)


def print_scenario_table(turns: list[int], model_key: str, model: dict,
                         budget_model: bool, retry_multiplier: float) -> None:
    """Print alternative project scenarios as Markdown using one model's rates."""
    labels = ("Low", "Base", "High")
    costs = [_turn_cost(count, 1.0, model) for count in turns]
    print("| Scenario | Turns | Estimated cost |")
    print("|---|---:|---:|")
    for label, count, cost in zip(labels, turns, costs):
        print(f"| {label} | {count:,} | ${cost:,.2f} |")
    if budget_model:
        print(f"| High + 20% contingency | {turns[2]:,} | ${costs[2] * 1.20:,.2f} |")
        retry_turns = round(turns[1] * retry_multiplier)
        retry_cost = _turn_cost(retry_turns, 1.0, model)
        print(f"| Base × {retry_multiplier:g} retries sensitivity | {retry_turns:,} | ${retry_cost:,.2f} |")
    print(f"\nPPQ model: `{model_key}` ({model['name']}); prices per 1M tokens: "
          f"${model['input_per_M']:g} input / ${model['output_per_M']:g} output.")
    if budget_model:
        print("The contingency and retry sensitivity are separate alternatives; do not add them.")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Optimize model mix for project estimation using the cache-aware "
            "turn cost model (input=134k tok/turn @ 97% cache read / 3% cache "
            "write, output=1k tok/turn)."
        )
    )
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--turns", type=int, help="Estimated turn count for the deliverable (must be > 0)")
    group.add_argument(
        "--loc", type=int,
        help="DEPRECATED: converts to turns via turns = loc / 30. Prefer --turns.",
    )
    parser.add_argument("--quality", choices=["ultra-budget", "budget", "balanced", "premium"],
                        default="balanced", help="Quality tier (default: balanced)")
    parser.add_argument("--fetch", action="store_true", help="Force refresh prices from PPQ")
    parser.add_argument("--model", help="Price all turns on this exact PPQ model ID")
    parser.add_argument("--scenario-turns", help="Comma-separated low,base,high turns; requires --model")
    parser.add_argument("--budget-model", action="store_true",
                        help="Add separate high+20%% contingency and base×1.5 retry sensitivity")
    parser.add_argument("--retry-multiplier", type=float, default=1.5,
                        help="Retry sensitivity multiplier for --budget-model (default: 1.5)")
    parser.add_argument("--list-models", action="store_true", help="List available PPQ chat models")
    parser.add_argument("--provider", help="Filter --list-models by provider or model ID prefix")
    args = parser.parse_args()

    if not args.list_models and args.turns is None and args.loc is None:
        if not args.scenario_turns:
            parser.error("--turns, --loc, or --scenario-turns is required")
    if args.scenario_turns:
        try:
            scenario_turns = [int(value.strip()) for value in args.scenario_turns.split(",")]
        except ValueError:
            parser.error("--scenario-turns must contain three comma-separated integers")
        if len(scenario_turns) != 3 or any(value <= 0 for value in scenario_turns):
            parser.error("--scenario-turns must contain three positive integers: low,base,high")
        if scenario_turns != sorted(scenario_turns):
            parser.error("--scenario-turns must be ordered low,base,high")
        if not args.model:
            parser.error("--scenario-turns requires --model")
        if args.turns is not None or args.loc is not None:
            parser.error("use --scenario-turns without --turns or --loc")
        args.scenario_turn_values = scenario_turns
    if args.budget_model and not args.model:
        parser.error("--budget-model requires --model")
    if args.retry_multiplier <= 0:
        parser.error("--retry-multiplier must be positive")
    if args.turns is not None and args.turns <= 0:
        parser.error("--turns must be a positive integer")
    if args.loc is not None and args.loc <= 0:
        parser.error("--loc must be a positive integer")
    return args


def _resolve_turns(args: argparse.Namespace) -> int:
    if args.turns is not None:
        return args.turns
    print(
        "WARN: LOC-based estimate is deprecated; prefer --turns "
        f"(bridging via turns = loc / {LOC_PER_TURN})",
        file=sys.stderr,
    )
    return max(1, round(args.loc / LOC_PER_TURN))


def main() -> None:
    args = _parse_args()
    prices = load_prices(force_refresh=args.fetch)
    if os.path.exists(PRICES_CACHE):
        fetched_at = datetime.fromtimestamp(
            os.path.getmtime(PRICES_CACHE), timezone.utc
        ).strftime("%Y-%m-%d %H:%M UTC")
        print(f"PPQ price catalog cache: {fetched_at}")
    if args.list_models:
        for model_key, model in sorted(prices.items()):
            if args.provider and args.provider.lower() not in (model_key + " " + model["provider"]).lower():
                continue
            print(f"{model_key}\t${model['input_per_M']:.6g}/M in\t${model['output_per_M']:.6g}/M out\t{model['name']}")
        return
    if args.scenario_turns:
        model = prices.get(args.model)
        if model is None:
            print(f"ERROR: model {args.model!r} not found; refresh prices or use --list-models", file=sys.stderr)
            raise SystemExit(2)
        print_scenario_table(args.scenario_turn_values, args.model, model,
                             args.budget_model, args.retry_multiplier)
        return
    turns = _resolve_turns(args)
    if args.model:
        model = prices.get(args.model)
        if model is None:
            print(f"ERROR: model {args.model!r} not found; refresh prices or use --list-models", file=sys.stderr)
            raise SystemExit(2)
        cost = _turn_cost(turns, 1.0, model)
        result = {
            "turns": turns, "quality_tier": f"single: {args.model}",
            "total_tokens": int((INPUT_TOKENS_PER_TURN + OUTPUT_TOKENS_PER_TURN) * turns),
            "per_task_type": [{"category": "all tasks", "model": args.model,
                "model_name": model["name"], "input_per_M": model["input_per_M"],
                "output_per_M": model["output_per_M"], "share_pct": 100.0,
                "cost_usd": round(cost, 2)}],
            "total_cost_usd": round(cost, 2), "baseline_usd": None,
            "premium_single_usd": None, "cross_check_usd": round(turns * CROSS_CHECK_USD_PER_TURN, 2),
        }
    else:
        result = cost_estimate(turns, args.quality, prices)
    print_report(result)


if __name__ == "__main__":
    main()
