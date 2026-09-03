#!/usr/bin/env bash
# ralph.sh — external driver for the multi-agent-loop skill.
#
# The loop lives HERE, outside the model. Each iteration re-invokes the agent
# with the same prompt; the agent reads its state from disk (dagRobin,
# .claude/WATCHDOG.md, git status), does work, and exits. We only stop when
# the agent prints the completion promise AND dagRobin is verifiably empty.
#
# Usage:
#   scripts/ralph.sh [--max N] [--prompt FILE] [--worker claude|hermes] [-- extra agent args]
#
# Env:
#   RALPH_PROMPT   prompt file (default: .claude/PROMPT.md, else built-in)
#   RALPH_MAX      max iterations (default: 50)
#   RALPH_WORKER   claude | hermes (default: claude if available, else hermes)
#
# Exit codes: 0 hard stop reached; 2 max iterations; 3 TYPE C blocker; 1 error.

set -euo pipefail

PROMISE='<promise>HARD_STOP</promise>'
BLOCKED='<promise>BLOCKED_TYPE_C</promise>'
MAX="${RALPH_MAX:-50}"
PROMPT_FILE="${RALPH_PROMPT:-.claude/PROMPT.md}"
WORKER="${RALPH_WORKER:-}"
LEDGER=".claude/RALPH.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --max) MAX="$2"; shift 2 ;;
    --prompt) PROMPT_FILE="$2"; shift 2 ;;
    --worker) WORKER="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

require() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
require dagRobin
require jq

if [ -z "$WORKER" ]; then
  if command -v claude >/dev/null 2>&1; then WORKER=claude; else WORKER=hermes; fi
fi
require "$WORKER"

if [ -n "${CLAUDECODE:-}" ]; then
  echo "ralph.sh must run from a plain shell, not inside Claude Code (nested sessions lose the handle)" >&2
  exit 1
fi

[ -f .dagrobin/db ] || dagRobin init

default_prompt() {
  cat <<'EOF'
Use the multi-agent-loop skill. You are one iteration of an external Ralph
driver: read state from disk first (Re-entry Protocol), do the next unit of
work, commit it, and exit. Print <promise>HARD_STOP</promise> ONLY when the
Hard Stop Condition holds. Print <promise>BLOCKED_TYPE_C</promise> ONLY when
every remaining item is TYPE C. Otherwise just end after committing — the
driver re-invokes you.
EOF
}

prompt() {
  if [ -f "$PROMPT_FILE" ]; then cat "$PROMPT_FILE"; else default_prompt; fi
}

run_worker() {
  case "$WORKER" in
    claude) claude -p "$(prompt)" --dangerously-skip-permissions "$@" ;;
    hermes) hermes -z "$(prompt)" --yolo "$@" ;;
    *) echo "unknown worker: $WORKER" >&2; exit 1 ;;
  esac
}

dagrobin_open() {
  # count tasks whose status is not done
  dagRobin list --format json 2>/dev/null \
    | jq '[.[] | select(.status != "done" and .status != "Done")] | length' 2>/dev/null \
    || echo 0
}

mkdir -p .claude
[ -f "$LEDGER" ] || echo "# ralph ledger — base $(git rev-parse --short HEAD 2>/dev/null || echo none)" > "$LEDGER"

i=0
while [ "$i" -lt "$MAX" ]; do
  i=$((i + 1))
  head_before=$(git rev-parse --short HEAD 2>/dev/null || echo none)
  out=$(run_worker "$@" 2>&1 | tee /dev/stderr) || true
  head_after=$(git rev-parse --short HEAD 2>/dev/null || echo none)
  open=$(dagrobin_open)
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

  printf '%s iter=%d head=%s->%s open=%s dirty=%s\n' \
    "$(date +%FT%T)" "$i" "$head_before" "$head_after" "$open" "$dirty" >> "$LEDGER"

  if printf '%s' "$out" | grep -q "$BLOCKED"; then
    echo "ralph: blocked on TYPE C after $i iterations" >&2
    exit 3
  fi

  if printf '%s' "$out" | grep -q "$PROMISE"; then
    if [ "$open" -eq 0 ] && [ "$dirty" -eq 0 ]; then
      echo "ralph: hard stop verified after $i iterations" >&2
      exit 0
    fi
    echo "ralph: promise printed but open=$open dirty=$dirty — rejected, continuing" >&2
    echo "  REJECTED promise (open=$open dirty=$dirty)" >> "$LEDGER"
  fi
done

echo "ralph: max iterations ($MAX) reached" >&2
exit 2
