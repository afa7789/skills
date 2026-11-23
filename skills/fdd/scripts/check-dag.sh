#!/usr/bin/env bash
# Validate the current dagRobin round against the fdd task contract.
set -euo pipefail

MAX=25
DB=""
USAGE="usage: check-dag.sh [--max N] [--db PATH]"

# shellcheck disable=SC2016  # jq program: $vars are jq's
CHECKS='
def filled: type == "string" and test("\\S");
def tagged($p): [.tags[]? | select(startswith($p))];
def faults($open):
  (if .metadata.check | filled then empty else "missing metadata.check" end),
  (if (.files | length) > 0 then empty else "empty files" end),
  (if .metadata["long-description"] | filled then empty else "missing metadata.long-description" end),
  (if (tagged("feature:") | length) == 1 then empty else "needs exactly one feature: tag" end),
  (tagged("phase:") as $p
    | if ($p | length) == 1 and ($p[0] | IN("phase:feature", "phase:harden", "phase:infra")) then empty
      else "needs exactly one phase: tag (feature|harden|infra)" end),
  (if tagged("phase:") == ["phase:harden"] and $open > 0
    then "phase:harden while \($open) phase:feature task(s) not Done" else empty end);
[.[] | select(.archived != true)] as $t
| ($t | map(select(.status != "Done"))) as $todo
| ($todo | map(select(.tags | index("phase:feature"))) | length) as $open
| ($t[] | . as $x | faults($open) | "\($x.id): \(.)"),
  (if ($todo | length) > $max then "round: \($todo | length) non-Done tasks > max \($max)" else empty end)
'

# shellcheck disable=SC2016
SUMMARY='
[.[] | select(.archived != true)] as $t
| "check-dag: OK \($t | length) active, \($t | map(select(.status != "Done")) | length) non-Done (max \($max))"
'

die() { echo "check-dag: $1" >&2; exit 2; }

parse_args() {
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || die "$USAGE"
    case "$1" in
      --max) MAX=$2 ;;
      --db) DB=$2 ;;
      *) die "$USAGE" ;;
    esac
    shift 2
  done
  case "$MAX" in '' | *[!0-9]*) die "--max must be a non-negative integer" ;; esac
}

list_tasks() {
  if [ -n "$DB" ]; then dagRobin -d "$DB" list --format json; else dagRobin list --format json; fi
}

main() {
  parse_args "$@"
  command -v jq >/dev/null || die "jq is required"
  local json problems
  json=$(list_tasks)
  problems=$(jq -r --argjson max "$MAX" "$CHECKS" <<<"$json")
  if [ -n "$problems" ]; then
    printf '%s\n' "$problems"
    echo "check-dag: FAIL $(wc -l <<<"$problems" | tr -d ' ') problem(s)"
    exit 1
  fi
  jq -r --argjson max "$MAX" "$SUMMARY" <<<"$json"
}

main "$@"
