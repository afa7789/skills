#!/usr/bin/env bash
# stop-gate.sh — Claude Code `Stop` hook for the multi-agent-loop skill.
#
# Ralph inside the session: every time Claude tries to end its turn, this
# script checks whether the loop is really done. If not, it returns
# {"decision":"block","reason":...} and Claude cannot stop — the reason is
# injected as the next prompt.
#
# Armed ONLY while `.claude/LOOP_ACTIVE` exists in the cwd (the skill creates
# it on entry and removes it on HARD_STOP / BLOCKED_TYPE_C). Any other
# session, any other project: exits 0 immediately, no effect.
#
# Allow stop when:  HARD_STOP or BLOCKED_TYPE_C printed AND dagRobin has no open tasks AND tree clean
# Also allow when:  WATCHDOG.md's last line is STILL_WORKING AND tree clean (live-worker exemption)
# Also allow when:  iteration count > RALPH_MAX (default 50) — safety valve
# Otherwise:        block, with the concrete reason.
#
# stdin: {"session_id","transcript_path","stop_hook_active",...}

set -u

SENTINEL=".claude/LOOP_ACTIVE"
[ -f "$SENTINEL" ] || exit 0
[ -e .dagrobin/db ] || exit 0

MAX="${RALPH_MAX:-50}"
input=$(cat)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

# iteration counter lives in the sentinel
iter=$(head -n1 "$SENTINEL" 2>/dev/null | tr -dc '0-9')
iter=$(( ${iter:-0} + 1 ))
printf '%s\n' "$iter" > "$SENTINEL"

allow() { rm -f "$SENTINEL"; printf '{"systemMessage":"multi-agent-loop: %s"}\n' "$1"; exit 0; }
block() {
  printf '{"decision":"block","reason":%s}\n' \
    "$(printf '%s' "$1" | jq -Rs .)"
  exit 0
}

if [ "$iter" -gt "$MAX" ]; then
  allow "safety valve: $MAX iterations reached, loop released"
fi

# last assistant text from the transcript (jsonl)
last=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
    "$transcript" 2>/dev/null | tail -n 40)
fi

promise=none
case "$last" in
  *'<promise>HARD_STOP</promise>'*) promise=hard_stop ;;
  *'<promise>BLOCKED_TYPE_C</promise>'*) promise=blocked ;;
esac

open=$(dagRobin list --format json 2>/dev/null \
  | jq '[.[] | select(.status != "done" and .status != "Done")] | length' 2>/dev/null)
open=${open:-0}
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# TYPE C creates no dagRobin task, so a genuine BLOCKED_TYPE_C state is quiescent too —
# gate it on open/dirty exactly like HARD_STOP.
if [ "$promise" = blocked ] && [ "$open" -eq 0 ] && [ "$dirty" -eq 0 ]; then
  allow "stopped on TYPE C after $iter iterations (open=$open dirty=$dirty)"
fi

if [ "$promise" = hard_stop ] && [ "$open" -eq 0 ] && [ "$dirty" -eq 0 ]; then
  allow "hard stop verified after $iter iterations"
fi

# Live-worker exemption (§Turn Contract): a dispatched-and-recorded worker with a clean tree
# is a valid turn end, even with no promise — the wakeup or next poll re-invokes us.
last_watchdog=$(tail -n1 .claude/WATCHDOG.md 2>/dev/null || true)
case "$last_watchdog" in
  *STILL_WORKING*)
    if [ "$dirty" -eq 0 ]; then
      allow "live worker recorded in WATCHDOG.md, tree clean, iteration $iter"
    fi
    ;;
esac

reason="multi-agent-loop iteration $iter/$MAX — turn end rejected. "
case "$promise" in
  hard_stop) reason+="You printed HARD_STOP but open dagRobin tasks=$open, uncommitted files=$dirty. " ;;
  blocked)   reason+="You printed BLOCKED_TYPE_C but open dagRobin tasks=$open, uncommitted files=$dirty — TYPE C creates no task, so this isn't a real TYPE-C-only state. " ;;
  none)      reason+="No promise printed; open dagRobin tasks=$open, uncommitted files=$dirty. " ;;
esac
reason+="Run Phase 0 Re-entry Protocol: git status → finish+commit the diff; .claude/WATCHDOG.md → give every worker a verdict; dagRobin ready → dispatch. "
reason+="End the turn only per the Turn Contract (committed iteration, <promise>HARD_STOP</promise>, or <promise>BLOCKED_TYPE_C</promise>)."
block "$reason"
