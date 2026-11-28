#!/usr/bin/env bash
# dag-loop driver tests: --host fake on scratch repos with scratch dagRobin DBs. Exit 1 on any failing case.
# shellcheck disable=SC2016 # fake host commands and checks expand inside the worktree, not here
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DRIVER="$HERE/../scripts/dag-loop.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset DAGROBIN_DB CLAUDECODE DAGLOOP_KEEP_API_KEY HERDR_ENV
FAILED=0 R="" RC=0 WHY=""

task() { # id title tags check [files] [deps] [priority]
  printf -- "- id: %s\n  title: %s\n  priority: %s\n  deps: [%s]\n  files: [%s]\n  tags: [%s]\n  metadata:\n    long-description: Spec for %s.\n    check: '%s'\n" \
    "$1" "$2" "${7:-1}" "${6:-}" "${5:-}" "$3" "$1" "$4"
}

repo() { # name [task-yaml...]: fresh repo with one commit and, given tasks, a project DB holding them
  R="$TMP/$1"
  shift
  export RUNS="$R.runs"
  mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" config user.email test@example.com
  git -C "$R" config user.name test
  git -C "$R" config commit.gpgsign false
  echo .dagrobin/ >"$R/.gitignore"
  git -C "$R" add .gitignore
  git -C "$R" commit -qm base
  [ $# -gt 0 ] || return 0
  printf '%s\n' "$@" >"$R.yaml"
  (cd "$R" && dagRobin init >/dev/null && dagRobin import "$R.yaml" >/dev/null)
}

drive() {
  RC=0
  (cd "$R" && bash "$DRIVER" --host fake "$@") >"$R.out" 2>&1 || RC=$?
}

field() { (cd "$R" && dagRobin list --format json) | jq -r --arg id "$1" ".[] | select(.id == \$id) | $2 // \"\""; }
commits() { git -C "$R" rev-list --count HEAD; }
runs() { if [ -f "$RUNS" ]; then wc -l <"$RUNS" | tr -d ' '; else echo 0; fi; }

is() { [ "$1" = "$2" ] || { WHY="expected '$2', got '$1'"; return 1; }; }
has() { grep -q -- "$2" "$1" || { WHY="'$2' not found in $1"; return 1; }; }
before() { # file a b: first line matching a comes before first line matching b
  local a b
  a=$(grep -n -m1 -- "$2" "$1" | cut -d: -f1)
  b=$(grep -n -m1 -- "$3" "$1" | cut -d: -f1)
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then return 0; fi
  WHY="'$2' not logged before '$3'"
  return 1
}
tidy() { # the driver leaves no worktree, branch, lock or stray file behind
  is "$(git -C "$R" status --porcelain)" "" &&
    is "$(ls -A "$R/.worktrees" 2>/dev/null)" "" &&
    is "$(git -C "$R" branch --list 'dagloop/*')" "" &&
    is "$(ls -d "$R/.git/dag-loop.lock" 2>/dev/null)" ""
}

case_a_pass() {
  repo a "$(task f001-login 'Login with email and password' 'feature:F-001, phase:feature' 'test -f src/login.txt' src/login.txt)"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; echo "${CLAUDECODE-unset} ${ANTHROPIC_API_KEY-unset}" >"$RUNS.env"
    mkdir -p src && echo ok >src/login.txt && git add -A && git commit -qm wip'
  export CLAUDECODE=1 ANTHROPIC_API_KEY=secret
  drive
  unset CLAUDECODE ANTHROPIC_API_KEY
  is "$RC" 0 && is "$(field f001-login .status)" Done && is "$(commits)" 2 && is "$(runs)" 1 &&
    is "$(git -C "$R" log -1 --format=%s)" 'feat(F-001): Login with email and password' &&
    is "$(cat "$RUNS.env")" 'unset unset' && tidy
}

case_b_check_fails_then_blocked() {
  repo b "$(task f002-x 'Broken check' 'feature:F-002, phase:feature' 'test -f src/never.txt')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; echo y >y.txt && git add -A && git commit -qm wip'
  drive --retries 1
  is "$RC" 3 && is "$(field f002-x .status)" Blocked && is "$(field f002-x .metadata.notes)" 'dag-loop check-failed' &&
    is "$(runs)" 2 && is "$(commits)" 1 && has "$R/.git/dag-loop.d/f002-x.prompt" 'Previous attempt failed: check-failed' && tidy
}

# Rule: a host that exits non-zero without committing (or times out) is a host fault, not a task verdict.
# It counts as an attempt; if the last attempt was one, the task goes back to Pending and the driver exits 1.
case_c_crash_returns_to_pending() {
  repo c "$(task f003-c 'Crashing host' 'feature:F-003, phase:feature' 'true')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; echo boom >&2; exit 1'
  drive --retries 1
  is "$RC" 1 && is "$(field f003-c .status)" Pending && is "$(runs)" 2 && is "$(commits)" 1 &&
    has "$R.out" 'f003-c attempt 2 failed: crash' && tidy
}

case_d_no_commit_fails() {
  repo d "$(task f004-d 'Forgets to commit' 'feature:F-004, phase:feature' 'true')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; echo dirty >dirty.txt'
  drive --retries 1
  is "$RC" 3 && is "$(field f004-d .status)" Blocked && is "$(field f004-d .metadata.notes)" 'dag-loop no-commit' &&
    is "$(runs)" 2 && is "$(commits)" 1 && tidy
}

case_e_refuses_global_db() {
  local unset_rc
  repo e
  drive
  unset_rc=$RC
  export DAGROBIN_DB="$HOME/.local/share/dagRobin/dagrobin.db"
  drive
  unset DAGROBIN_DB
  is "$unset_rc" 1 && is "$RC" 1 && has "$R.out" 'refusing the global dagRobin DB' &&
    is "$(ls -A "$HOME")" ""
}

case_f_exit_3_when_only_blocked_or_unready() {
  repo f "$(task ok1 'Works' 'feature:F-010, phase:feature' 'test -f ok1.txt')" \
    "$(task bad1 'Never passes' 'feature:F-011, phase:feature' 'false')" \
    "$(task dep1 'Waits on bad1' 'feature:F-012, phase:feature' 'true' '' bad1)" \
    "$(task nophase 'No phase tag' 'feature:F-013' 'true')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; id=$(basename "$PWD"); echo x >"$id.txt" && git add -A && git commit -qm "$id"'
  drive --batch 1 --retries 0
  is "$RC" 3 && is "$(field ok1 .status)" Done && is "$(field bad1 .status)" Blocked &&
    is "$(field dep1 .status)" Pending && is "$(field nophase .status)" Blocked &&
    has "$R.out" 'nophase blocked: bad-contract' && is "$(runs)" 2 && is "$(commits)" 2 && tidy
}

# Also: priority 1 runs before priority 2 although its id sorts later, and DAGLOOP_KEEP_API_KEY=1 keeps the key.
case_g_phase_commit_messages() {
  repo g "$(task h001-edge 'Reject empty password' 'feature:F-001, phase:harden' 'test -f h001-edge.txt' '' '' 2)" \
    "$(task i001-ci 'Set up CI' 'feature:infra, phase:infra' 'test -f i001-ci.txt' '' '' 1)"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; echo "${ANTHROPIC_API_KEY-unset}" >"$RUNS.env"
    id=$(basename "$PWD"); echo x >"$id.txt" && git add -A && git commit -qm "$id"'
  export ANTHROPIC_API_KEY=kept DAGLOOP_KEEP_API_KEY=1
  drive --batch 1
  unset ANTHROPIC_API_KEY DAGLOOP_KEEP_API_KEY
  is "$RC" 0 && is "$(commits)" 3 && is "$(cat "$RUNS.env")" kept &&
    is "$(git -C "$R" log -2 --format=%s | tr '\n' '|')" 'test(F-001): Reject empty password|chore(infra): Set up CI|' && tidy
}

case_h_verify_fail_resets_main() {
  repo h "$(task v001 'Passes only in the worktree' 'feature:F-020, phase:feature' 'test -f v.txt && case $PWD in */.worktrees/*) true ;; *) false ;; esac')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; echo v >v.txt && git add -A && git commit -qm wip'
  drive --retries 1
  is "$RC" 3 && is "$(field v001 .status)" Blocked && is "$(field v001 .metadata.notes)" 'dag-loop verify-failed' &&
    is "$(runs)" 2 && is "$(commits)" 1 && tidy
}

case_i_timeout_kills_host() {
  local start=$SECONDS
  repo i "$(task t001 'Hangs' 'feature:F-030, phase:feature' 'true')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; sleep 30'
  drive --retries 0 --timeout 2
  is "$RC" 1 && is "$(field t001 .status)" Pending && has "$R.out" 't001 attempt 1 failed: timeout' &&
    is "$((SECONDS - start < 15))" 1 && tidy
}

# p1 and p2 declare disjoint files and run together, but both create log.txt: p2 merges second, conflicts,
# and passes on retry from the new HEAD. p3 shares a file with p1, so it waits for the next round under --batch 1.
case_j_parallel_slots() {
  repo j "$(task p1 'Parallel one' 'feature:F-040, phase:feature' 'grep -qx p1 log.txt' a.txt)" \
    "$(task p2 'Parallel two' 'feature:F-041, phase:feature' 'grep -qx p2 log.txt' b.txt)" \
    "$(task p3 'Overlaps p1' 'feature:F-042, phase:feature' 'grep -qx p3 log.txt' a.txt)"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; id=$(basename "$PWD"); [ "$id" != p2 ] || sleep 2; echo "$id" >>log.txt && git add -A && git commit -qm "$id"'
  drive --slots 3 --batch 1 --retries 1
  local log="$R/.git/dag-loop.log"
  is "$RC" 0 && is "$(commits)" 4 && has "$log" 'p2 attempt 1 failed: merge-conflict' &&
    before "$log" 'p2 attempt 1/' 'p1 done' && before "$log" 'p1 done' 'p3 attempt 1/' && tidy
}

# Checks leave untracked build output in the main tree; later merges must not treat it as a dirty tree.
case_k_check_artifacts_do_not_block() {
  repo k "$(task k1 'First' 'feature:F-050, phase:feature' 'touch build.tmp && test -f k1.txt')" \
    "$(task k2 'Second' 'feature:F-051, phase:feature' 'touch build.tmp && test -f k2.txt')"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; id=$(basename "$PWD"); echo x >"$id.txt" && git add "$id.txt" && git commit -qm "$id"'
  drive --batch 1
  is "$RC" 0 && is "$(field k2 .status)" Done && is "$(commits)" 3 && [ -f "$R/build.tmp" ] &&
    is "$(git -C "$R" status --porcelain --untracked-files=no)" "" && is "$(ls -A "$R/.worktrees" 2>/dev/null)" ""
}

# Inside herdr (HERDR_ENV=1) milestones become herdr notifications; outside, herdr is never called.
case_l_herdr_notifications() {
  repo l "$(task l1 'Notify' 'feature:F-060, phase:feature' 'test -f l1.txt')"
  mkdir -p "$TMP/bin"
  printf '#!/bin/sh\necho "$*" >>"%s"\n' "$TMP/herdr.calls" >"$TMP/bin/herdr"
  chmod +x "$TMP/bin/herdr"
  export DAGLOOP_FAKE_CMD='echo x >l1.txt && git add l1.txt && git commit -qm l1'
  PATH="$TMP/bin:$PATH" drive
  is "$RC" 0 && [ ! -f "$TMP/herdr.calls" ] || { WHY="herdr called outside herdr"; return 1; }
  repo l2 "$(task l1 'Notify' 'feature:F-060, phase:feature' 'test -f l1.txt')"
  HERDR_ENV=1 PATH="$TMP/bin:$PATH" drive
  is "$RC" 0 && has "$TMP/herdr.calls" 'notification show dag-loop --body l1 done' &&
    has "$TMP/herdr.calls" 'notification show dag-loop --body all tasks done'
}

# Default (--batch all): a single agent run handles all ready tasks (even with shared files) in one worktree.
case_m_batch_default_all() {
  repo m "$(task b1 'First' 'feature:F-070, phase:feature' 'test -f b1.txt' shared.txt)" \
    "$(task b2 'Second' 'feature:F-071, phase:feature' 'test -f b2.txt' shared.txt)" \
    "$(task b3 'Third' 'feature:F-072, phase:feature' 'test -f b3.txt' other.txt)"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; for id in $DAGLOOP_TASKS; do echo ok >"$id.txt"; done; git add -A && git commit -qm batch'
  drive
  is "$RC" 0 && is "$(runs)" 1 && is "$(commits)" 2 &&
    is "$(field b1 .status)" Done && is "$(field b2 .status)" Done && is "$(field b3 .status)" Done &&
    is "$(git -C "$R" log -1 --format=%s)" 'feat(F-070,F-071,F-072): 3 tasks' && tidy
}

# --batch N caps tasks per agent; overlapping files group into the same slot while disjoint files split across slots.
case_n_batch_cap_and_overlap() {
  repo n "$(task n1 'One' 'feature:F-080, phase:feature' 'test -f n1.txt' a.txt)" \
    "$(task n2 'Two' 'feature:F-081, phase:feature' 'test -f n2.txt' b.txt)" \
    "$(task n3 'Three' 'feature:F-082, phase:feature' 'test -f n3.txt' a.txt)"
  export DAGLOOP_FAKE_CMD='echo "$DAGLOOP_TASKS" >>"$RUNS"; for id in $DAGLOOP_TASKS; do echo ok >"$id.txt"; done; git add -A && git commit -qm batch'
  drive --slots 2 --batch 2
  is "$RC" 0 && is "$(runs)" 2 &&
    has "$RUNS" 'n1 n3' && has "$RUNS" 'n2' && tidy
}

# Partial failure in a batch: only the failing task is Blocked; passing siblings requeue and succeed next round.
case_o_batch_partial_failure() {
  repo o "$(task o1 'Passes' 'feature:F-090, phase:feature' 'test -f o1.txt' a.txt)" \
    "$(task o2 'Always fails' 'feature:F-091, phase:feature' 'test -f never.txt' b.txt)"
  export DAGLOOP_FAKE_CMD='echo run >>"$RUNS"; for id in $DAGLOOP_TASKS; do echo ok >"$id.txt"; done; git add -A && git commit -qm batch'
  drive --retries 0
  is "$RC" 3 && is "$(field o1 .status)" Done && is "$(field o2 .status)" Blocked &&
    is "$(field o2 .metadata.notes)" 'dag-loop check-failed' && is "$(runs)" 2 && is "$(commits)" 2 && tidy
}

if ! command -v dagRobin >/dev/null || ! command -v jq >/dev/null; then
  echo "FAIL prerequisites: dagRobin and jq must be on PATH"
  exit 1
fi
for c in case_a_pass case_b_check_fails_then_blocked case_c_crash_returns_to_pending case_d_no_commit_fails \
  case_e_refuses_global_db case_f_exit_3_when_only_blocked_or_unready case_g_phase_commit_messages \
  case_h_verify_fail_resets_main case_i_timeout_kills_host case_j_parallel_slots case_k_check_artifacts_do_not_block \
  case_l_herdr_notifications case_m_batch_default_all case_n_batch_cap_and_overlap case_o_batch_partial_failure; do
  WHY=""
  if "$c"; then
    echo "PASS $c"
  else
    echo "FAIL $c: $WHY"
    tail -n 15 "$R.out" | sed 's/^/    /'
    FAILED=$((FAILED + 1))
  fi
done
[ "$FAILED" -eq 0 ] || { echo "$FAILED case(s) failed"; exit 1; }
echo "all cases passed"
