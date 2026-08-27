#!/usr/bin/env python3
"""Estimate dev-hours from git history using the session-gap heuristic.

Algorithm (git-hours / git-estimate lineage):
  1. Group commits per author, sorted by timestamp.
  2. Two consecutive commits belong to the same session when the gap is
     <= --max-gap minutes. A larger gap opens a new session.
  3. Each session's duration is (last - first) + --first-commit minutes,
     which pays for the work that preceded the session's first commit.

Use it to recalibrate the estimator skill against a real repository:
    python3 scripts/git-hours.py --repo ../../../some-project
"""

from __future__ import annotations

import argparse
import subprocess
from collections import defaultdict
from dataclasses import dataclass

SECONDS_PER_HOUR = 3600.0


@dataclass(frozen=True)
class AuthorStats:
    author: str
    commits: int
    hours: float
    active_days: int

    @property
    def commits_per_active_day(self) -> float:
        return self.commits / self.active_days if self.active_days else 0.0

    @property
    def hours_per_active_day(self) -> float:
        return self.hours / self.active_days if self.active_days else 0.0


def read_commits(repo: str, since: str | None) -> dict[str, list[int]]:
    cmd = ["git", "-C", repo, "log", "--no-merges", "--pretty=format:%at|%aE"]
    if since:
        cmd.append(f"--since={since}")
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    by_author: dict[str, list[int]] = defaultdict(list)
    for line in out.splitlines():
        if "|" not in line:
            continue
        ts, email = line.split("|", 1)
        by_author[email.strip().lower()].append(int(ts))
    return by_author


def session_hours(timestamps: list[int], max_gap_min: int, first_commit_min: int) -> float:
    if not timestamps:
        return 0.0
    ordered = sorted(timestamps)
    max_gap = max_gap_min * 60
    total = float(first_commit_min * 60)
    for prev, curr in zip(ordered, ordered[1:]):
        gap = curr - prev
        total += gap if gap <= max_gap else first_commit_min * 60
    return total / SECONDS_PER_HOUR


def active_days(timestamps: list[int]) -> int:
    return len({ts // 86400 for ts in timestamps})


def collect(repo: str, since: str | None, max_gap: int, first_commit: int) -> list[AuthorStats]:
    stats = [
        AuthorStats(
            author=author,
            commits=len(ts),
            hours=session_hours(ts, max_gap, first_commit),
            active_days=active_days(ts),
        )
        for author, ts in read_commits(repo, since).items()
    ]
    return sorted(stats, key=lambda s: s.hours, reverse=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="path to the git repository")
    parser.add_argument("--since", default=None, help="git --since expression, e.g. '1 year ago'")
    parser.add_argument("--max-gap", type=int, default=120, help="session gap in minutes (default 120)")
    parser.add_argument(
        "--first-commit",
        type=int,
        default=120,
        help="minutes credited before a session's first commit (default 120)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    stats = collect(args.repo, args.since, args.max_gap, args.first_commit)
    print(f"{'author':<38} {'commits':>8} {'hours':>9} {'act.days':>9} {'c/day':>7} {'h/day':>7}")
    for s in stats:
        print(
            f"{s.author:<38} {s.commits:>8} {s.hours:>9.1f} {s.active_days:>9} "
            f"{s.commits_per_active_day:>7.1f} {s.hours_per_active_day:>7.1f}"
        )
    total_h = sum(s.hours for s in stats)
    total_c = sum(s.commits for s in stats)
    print(f"\nTOTAL: {total_c} commits, {total_h:.1f} h, {total_h / 8:.1f} person-days @8h")


if __name__ == "__main__":
    main()
