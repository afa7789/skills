#!/usr/bin/env python3
"""Turn cost / dev-hours arithmetic for the estimator skill.

Encodes the formulas from SKILL.md as code so the model never hand-computes
them. Every constant below cites the SKILL.md section it was pulled from —
re-run the calibration scripts (`session-tokens.py`, `git-hours.py`) if those
sections change and update the constants here to match.

Usage:
    python3 scripts/estimate-cost.py --turns 100
    python3 scripts/estimate-cost.py --turns 100 --features simple,medium,complex \\
        --rhythm sustained --json
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass

# --- "Token Estimation — Turn-Based (MEASURED)" -----------------------------
# Total billed tokens per turn (min/median/max), and output tokens per turn.
TOTAL_TOKENS_PER_TURN = {"low": 44_000.0, "median": 135_000.0, "high": 282_000.0}
OUTPUT_TOKENS_PER_TURN = {"low": 290.0, "median": 1_000.0, "high": 1_840.0}
CACHE_READ_SHARE = 0.97
CACHE_WRITE_SHARE = 0.03

# --- "Cost Calculation Formula" ---------------------------------------------
DIRECT_ANCHOR_USD_PER_TURN = 0.13
CROSS_CHECK_WARN_PCT = 0.20

# --- "Feature-Span Calibration (Calendar Days, First→Last Commit)" ----------
FEATURE_SPAN_DAYS = {
    "trivial": 1.0,
    "simple": 1.0,
    "medium": 2.0,
    "complex": 8.0,
    "critical": 28.0,
}

# --- "Rhythm Profiles (Real Patterns)" --------------------------------------
RHYTHM_MULTIPLIERS = {
    "sustained": 1.0,
    "sprint-and-rest": 1.4,
    "build+tail": 1.6,
    "burst+gap": 1.8,
    "polish-heavy": 1.5,
}

# --- "Working-Day Conversion" -----------------------------------------------
# "Rule of thumb: ... roughly 1.5 active days per calendar week" is the honest
# solo-side-project default when no rhythm-specific measurement exists.
DEFAULT_ACTIVE_DAYS_PER_WEEK = 1.5

# --- "Dev-Hours Calibration (MEASURED)" -------------------------------------
DEFAULT_HOURS_PER_ACTIVE_DAY = 5.5  # band 5.0-7.0
DEFAULT_LOC_PER_HOUR = 820.0  # median 823, band 300-1300

# --- "Reconciliation rule" ---------------------------------------------------
RECONCILE_LOW_RATIO = 1.5
RECONCILE_HIGH_RATIO = 2.5

# --- "Team scaling" ----------------------------------------------------------
TEAM_CALENDAR_DIVISOR = {1: 1.0, 2: 1.6, 3: 2.1, 4: 2.5}
TEAM_HOURS_MULTIPLIER = {1: 1.00, 2: 1.15, 3: 1.30, 4: 1.50}


@dataclass(frozen=True)
class CostBand:
    level: str
    total_tokens: float
    input_tokens: float
    cache_read_tokens: float
    cache_write_tokens: float
    output_tokens: float
    cost_usd: float


@dataclass(frozen=True)
class WallClock:
    calendar_days: float
    working_days: float
    dev_hours_cadence: float
    dev_hours_throughput: float | None
    dev_hours_reconciled_low: float
    dev_hours_reconciled_high: float
    reconcile_note: str
    dev_hours_final_low: float
    dev_hours_final_high: float
    dev_cost_usd: float | None = None


def team_factor(team: int) -> tuple[float, float]:
    key = min(max(team, 1), 4)
    return TEAM_CALENDAR_DIVISOR[key], TEAM_HOURS_MULTIPLIER[key]


def cost_band(
    level: str,
    turns: int,
    input_price: float,
    output_price: float,
    cache_read_mult: float,
    cache_write_mult: float,
) -> CostBand:
    total_tokens = turns * TOTAL_TOKENS_PER_TURN[level]
    output_tokens = turns * OUTPUT_TOKENS_PER_TURN[level]
    input_tokens = total_tokens - output_tokens
    cache_read_tokens = input_tokens * CACHE_READ_SHARE
    cache_write_tokens = input_tokens * CACHE_WRITE_SHARE
    cost_usd = (
        cache_read_tokens * input_price * cache_read_mult
        + cache_write_tokens * input_price * cache_write_mult
        + output_tokens * output_price
    ) / 1_000_000
    return CostBand(
        level=level,
        total_tokens=total_tokens,
        input_tokens=input_tokens,
        cache_read_tokens=cache_read_tokens,
        cache_write_tokens=cache_write_tokens,
        output_tokens=output_tokens,
        cost_usd=cost_usd,
    )


def cross_check(median_cost: float, turns: int) -> tuple[float, float, bool]:
    anchor = turns * DIRECT_ANCHOR_USD_PER_TURN
    if anchor == 0:
        return anchor, 0.0, False
    pct_diff = abs(median_cost - anchor) / anchor
    return anchor, pct_diff, pct_diff > CROSS_CHECK_WARN_PCT


def parse_features(raw: str | None) -> list[str]:
    if not raw:
        return []
    text = raw.strip()
    if text.startswith("["):
        text = ",".join(str(x) for x in json.loads(text))
    labels = [x.strip().lower() for x in text.split(",") if x.strip()]
    unknown = sorted(set(labels) - set(FEATURE_SPAN_DAYS))
    if unknown:
        raise SystemExit(f"unknown complexity label(s): {unknown}; allowed: {sorted(FEATURE_SPAN_DAYS)}")
    return labels


def reconcile_hours(cadence: float, throughput: float) -> tuple[float, float, str]:
    lo, hi = min(cadence, throughput), max(cadence, throughput)
    if lo == 0:
        return lo, hi, "one estimator is zero — using the other"
    ratio = hi / lo
    if ratio <= RECONCILE_LOW_RATIO:
        return lo, hi, f"within {RECONCILE_LOW_RATIO}x — quoting the range"
    if ratio <= RECONCILE_HIGH_RATIO:
        return hi, hi, "1.5-2.5x apart — taking the higher estimator"
    return hi, hi, f"WARN: >{RECONCILE_HIGH_RATIO}x apart — re-check complexity/rhythm"


def compute_wall_clock(
    features: list[str],
    rhythm: str | None,
    polish_loop_rate: float,
    active_days_per_week: float,
    hours_per_active_day: float,
    net_loc: int | None,
    loc_per_hour: float,
    ai_factor: float,
    team: int,
    hourly_rate: float | None,
) -> WallClock:
    base_days = sum(FEATURE_SPAN_DAYS[f] for f in features)
    rhythm_mult = RHYTHM_MULTIPLIERS.get(rhythm, 1.0) if rhythm else 1.0
    calendar_divisor, hours_mult = team_factor(team)

    calendar_days = base_days * rhythm_mult * (1 + polish_loop_rate * 0.5) / calendar_divisor
    working_day_factor = active_days_per_week / 7
    working_days = calendar_days * working_day_factor

    dev_hours_cadence = working_days * hours_per_active_day
    dev_hours_throughput = net_loc / loc_per_hour if net_loc else None

    if dev_hours_throughput is None:
        lo = hi = dev_hours_cadence
        note = "throughput leg skipped (no --net-loc)"
    else:
        lo, hi, note = reconcile_hours(dev_hours_cadence, dev_hours_throughput)

    final_low = lo * ai_factor * hours_mult
    final_high = hi * ai_factor * hours_mult
    dev_cost_usd = None
    if hourly_rate is not None:
        dev_cost_usd = ((final_low + final_high) / 2) * hourly_rate

    return WallClock(
        calendar_days=calendar_days,
        working_days=working_days,
        dev_hours_cadence=dev_hours_cadence,
        dev_hours_throughput=dev_hours_throughput,
        dev_hours_reconciled_low=lo,
        dev_hours_reconciled_high=hi,
        reconcile_note=note,
        dev_hours_final_low=final_low,
        dev_hours_final_high=final_high,
        dev_cost_usd=dev_cost_usd,
    )


@dataclass(frozen=True)
class Report:
    turns: int
    bands: list[CostBand]
    anchor_usd: float
    cross_check_pct: float
    cross_check_warn: bool
    wall_clock: WallClock | None = None
    total_usd: float | None = None


def build_report(args: argparse.Namespace) -> Report:
    bands = [
        cost_band(level, args.turns, args.input_price, args.output_price,
                  args.cache_read_mult, args.cache_write_mult)
        for level in ("low", "median", "high")
    ]
    median_cost = bands[1].cost_usd
    anchor, pct_diff, warn = cross_check(median_cost, args.turns)

    wall_clock = None
    features = parse_features(args.features)
    if features:
        wall_clock = compute_wall_clock(
            features=features,
            rhythm=args.rhythm,
            polish_loop_rate=args.polish_loop_rate,
            active_days_per_week=args.active_days_per_week,
            hours_per_active_day=args.hours_per_active_day,
            net_loc=args.net_loc,
            loc_per_hour=args.loc_per_hour,
            ai_factor=args.ai_factor,
            team=args.team,
            hourly_rate=args.hourly_rate,
        )

    total_usd = None
    if wall_clock is not None and wall_clock.dev_cost_usd is not None:
        total_usd = wall_clock.dev_cost_usd + median_cost

    return Report(
        turns=args.turns,
        bands=bands,
        anchor_usd=anchor,
        cross_check_pct=pct_diff,
        cross_check_warn=warn,
        wall_clock=wall_clock,
        total_usd=total_usd,
    )


def band_to_dict(band: CostBand) -> dict[str, float | str]:
    return {
        "level": band.level,
        "total_tokens": band.total_tokens,
        "input_tokens": band.input_tokens,
        "cache_read_tokens": band.cache_read_tokens,
        "cache_write_tokens": band.cache_write_tokens,
        "output_tokens": band.output_tokens,
        "cost_usd": band.cost_usd,
    }


def wall_clock_to_dict(wc: WallClock) -> dict[str, float | str | None]:
    return {
        "calendar_days": wc.calendar_days,
        "working_days": wc.working_days,
        "dev_hours": {
            "cadence": wc.dev_hours_cadence,
            "throughput": wc.dev_hours_throughput,
            "reconciled_low": wc.dev_hours_reconciled_low,
            "reconciled_high": wc.dev_hours_reconciled_high,
            "reconcile_note": wc.reconcile_note,
            "final_low": wc.dev_hours_final_low,
            "final_high": wc.dev_hours_final_high,
        },
        "dev_cost_usd": wc.dev_cost_usd,
    }


def report_to_dict(report: Report) -> dict[str, object]:
    data: dict[str, object] = {
        "turns": report.turns,
        "bands": [band_to_dict(b) for b in report.bands],
        "anchor_usd": report.anchor_usd,
        "cross_check_pct": report.cross_check_pct,
        "cross_check_warn": report.cross_check_warn,
    }
    if report.wall_clock is not None:
        data.update(wall_clock_to_dict(report.wall_clock))
    if report.total_usd is not None:
        data["total_usd"] = report.total_usd
    return data


def print_text(report: Report) -> None:
    low, median, high = report.bands
    print(f"Turns: {report.turns}")
    print(f"Tokens/turn band: {low.total_tokens/report.turns:,.0f} / "
          f"{median.total_tokens/report.turns:,.0f} / {high.total_tokens/report.turns:,.0f}")
    print(f"  input:       {median.input_tokens:,.0f}")
    print(f"  cache read:  {median.cache_read_tokens:,.0f}")
    print(f"  cache write: {median.cache_write_tokens:,.0f}")
    print(f"  output:      {median.output_tokens:,.0f}")
    print(f"Cost band: ${low.cost_usd:,.2f} / ${median.cost_usd:,.2f} / ${high.cost_usd:,.2f}")
    print(f"Direct anchor ({report.turns} x $0.13): ${report.anchor_usd:,.2f} "
          f"({report.cross_check_pct:.1%} diff)")
    if report.cross_check_warn:
        print("WARN: median cost diverges >20% from the direct anchor — check pricing/cache split.")

    wc = report.wall_clock
    if wc is not None:
        print()
        print(f"Calendar days: {wc.calendar_days:.1f}")
        print(f"Working days:  {wc.working_days:.1f}")
        print(f"Dev-hours cadence:    {wc.dev_hours_cadence:.1f} h")
        if wc.dev_hours_throughput is not None:
            print(f"Dev-hours throughput: {wc.dev_hours_throughput:.1f} h")
        print(f"Dev-hours reconciled: {wc.dev_hours_reconciled_low:.1f}-"
              f"{wc.dev_hours_reconciled_high:.1f} h ({wc.reconcile_note})")
        print(f"Dev-hours final:      {wc.dev_hours_final_low:.1f}-{wc.dev_hours_final_high:.1f} h")
        if wc.dev_cost_usd is not None:
            print(f"Dev cost: ${wc.dev_cost_usd:,.2f}")
    if report.total_usd is not None:
        print(f"Total cost (dev + AI tokens): ${report.total_usd:,.2f}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--turns", type=int, required=True, help="estimated assistant turns")
    parser.add_argument("--input-price", type=float, default=5.0, help="USD per 1M input tokens (default Opus-tier 5.0)")
    parser.add_argument("--output-price", type=float, default=25.0, help="USD per 1M output tokens (default Opus-tier 25.0)")
    parser.add_argument("--cache-read-mult", type=float, default=0.10, help="cache-read price multiplier of input price")
    parser.add_argument("--cache-write-mult", type=float, default=1.25, help="cache-write price multiplier of input price")
    parser.add_argument("--features", default=None, help="CSV or JSON list of complexity labels")
    parser.add_argument("--rhythm", choices=sorted(RHYTHM_MULTIPLIERS), default=None)
    parser.add_argument("--polish-loop-rate", type=float, default=0.0, help="fraction 0-1 of polish-loop commits")
    parser.add_argument("--active-days-per-week", type=float, default=DEFAULT_ACTIVE_DAYS_PER_WEEK)
    parser.add_argument("--hours-per-active-day", type=float, default=DEFAULT_HOURS_PER_ACTIVE_DAY)
    parser.add_argument("--net-loc", type=int, default=None, help="net committed LOC (throughput leg)")
    parser.add_argument("--loc-per-hour", type=float, default=DEFAULT_LOC_PER_HOUR)
    parser.add_argument("--ai-factor", type=float, default=1.0)
    parser.add_argument("--team", type=int, default=1)
    parser.add_argument("--hourly-rate", type=float, default=None)
    parser.add_argument("--json", action="store_true", help="emit JSON instead of the text report")
    args = parser.parse_args(argv)
    if args.turns <= 0:
        parser.error("--turns must be > 0")
    return args


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    report = build_report(args)
    if args.json:
        print(json.dumps(report_to_dict(report), indent=2))
    else:
        print_text(report)


if __name__ == "__main__":
    main()
