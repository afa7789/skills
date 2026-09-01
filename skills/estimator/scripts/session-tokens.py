#!/usr/bin/env python3
"""Measure real token consumption from Claude Code session logs.

Reads ~/.claude/projects/*/*.jsonl and aggregates per-project billed usage:
raw input, cache creation, cache reads, output, and turn (assistant API call)
counts. Use it to recalibrate the estimator skill's turn-based constants
instead of guessing them.

    python3 scripts/session-tokens.py                 # per-project table
    python3 scripts/session-tokens.py --constants     # the derived constants
    python3 scripts/session-tokens.py --min-turns 50  # drop noise projects
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import statistics
from collections import Counter, defaultdict

# Premium-tier reference prices, USD per 1M tokens.
PRICE_IN = 5.00
PRICE_CACHE_WRITE = 6.25  # 1.25x input
PRICE_CACHE_READ = 0.50  # 0.10x input
PRICE_OUT = 25.00


def collect(root: str) -> dict[str, Counter]:
    per: dict[str, Counter] = defaultdict(Counter)
    for path in glob.glob(os.path.join(root, "*", "*.jsonl")):
        project = os.path.basename(os.path.dirname(path))
        with open(path, errors="ignore") as fh:
            for line in fh:
                if '"usage"' not in line:
                    continue
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                usage = (entry.get("message") or {}).get("usage") or {}
                if not usage:
                    continue
                counter = per[project]
                counter["in"] += usage.get("input_tokens", 0)
                counter["cw"] += usage.get("cache_creation_input_tokens", 0)
                counter["cr"] += usage.get("cache_read_input_tokens", 0)
                counter["out"] += usage.get("output_tokens", 0)
                counter["turns"] += 1
    return per


def total(c: Counter) -> int:
    return c["in"] + c["cw"] + c["cr"] + c["out"]


def cost(c: Counter) -> float:
    return (
        c["in"] * PRICE_IN
        + c["cw"] * PRICE_CACHE_WRITE
        + c["cr"] * PRICE_CACHE_READ
        + c["out"] * PRICE_OUT
    ) / 1_000_000


def band(values: list[float]) -> tuple[float, float, float]:
    ordered = sorted(values)
    return ordered[0], statistics.median(ordered), ordered[-1]


def print_projects(rows: list[tuple[str, Counter]]) -> None:
    header = (
        f"{'project':46}{'turns':>7}{'tokens':>15}{'tok/turn':>10}"
        f"{'out/turn':>9}{'cacheR':>8}{'USD':>9}{'$/turn':>8}"
    )
    print(header)
    print("-" * len(header))
    for name, c in rows:
        tok = total(c)
        print(
            f"{name[-46:]:46}{c['turns']:>7,}{tok:>15,}{tok // c['turns']:>10,}"
            f"{c['out'] // c['turns']:>9,}{100 * c['cr'] / max(tok, 1):>7.0f}%"
            f"{cost(c):>9,.0f}{cost(c) / c['turns']:>8.3f}"
        )


def print_constants(rows: list[tuple[str, Counter]]) -> None:
    tok_per_turn = [total(c) / c["turns"] for _, c in rows]
    out_per_turn = [c["out"] / c["turns"] for _, c in rows]
    usd_per_turn = [cost(c) / c["turns"] for _, c in rows]
    cache_share = [c["cr"] / max(total(c), 1) for _, c in rows]

    print(f"\nDerived constants (n = {len(rows)} projects)\n")
    print(f"{'constant':28}{'min':>14}{'median':>14}{'max':>14}")
    print("-" * 70)
    for label, values, fmt in [
        ("tokens / turn", tok_per_turn, ",.0f"),
        ("output tokens / turn", out_per_turn, ",.0f"),
        ("USD / turn (premium)", usd_per_turn, ",.3f"),
        ("cache-read share", cache_share, ".2%"),
    ]:
        lo, mid, hi = band(values)
        print(f"{label:28}{lo:>14{fmt}}{mid:>14{fmt}}{hi:>14{fmt}}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        default=os.path.expanduser("~/.claude/projects"),
        help="Claude Code projects directory",
    )
    parser.add_argument("--min-turns", type=int, default=25)
    parser.add_argument("--constants", action="store_true", help="print only the constants")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    per = collect(args.root)
    rows = [(k, v) for k, v in per.items() if v["turns"] >= args.min_turns]
    if not rows:
        print("No sessions found. Check --root / --min-turns.")
        return
    rows.sort(key=lambda kv: -cost(kv[1]))
    if not args.constants:
        print_projects(rows)
        grand = Counter()
        for _, c in rows:
            grand.update(c)
        print("-" * 112)
        print(
            f"{'ALL':46}{grand['turns']:>7,}{total(grand):>15,}"
            f"{total(grand) // grand['turns']:>10,}{grand['out'] // grand['turns']:>9,}"
            f"{100 * grand['cr'] / max(total(grand), 1):>7.0f}%"
            f"{cost(grand):>9,.0f}{cost(grand) / grand['turns']:>8.3f}"
        )
    print_constants(rows)


if __name__ == "__main__":
    main()
