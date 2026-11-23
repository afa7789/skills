#!/usr/bin/env bash
# dag-loop: run dagRobin's ready tasks through a headless coding agent, one git worktree per task.
# Usage: dag-loop.sh --host claude|codex|opencode|pi|omp|hermes|fake [--slots 1] [--retries 2] [--timeout 1800] [--max-cost 2]
# Exit: 0 all tasks done; 3 only blocked/unready tasks remain; 1 error (or ready tasks left after host crash/timeout).
# shellcheck disable=SC2016 # single-quoted strings are jq programs
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=adapters.sh
. "$HERE/adapters.sh"
TEMPLATE="$HERE/../prompts/worker.md"

HOST="" SLOTS=1 RETRIES=2 TIMEOUT=1800 MAX_COST=2
ROOT="" LOCK="" STATE="" READY="" LOG=/dev/null
TRIED="" INFLIGHT="" REASON="" PRE=""

JQ_DEFS='def tag($k): [.tags[]? | select(startswith($k + ":")) | ltrimstr($k + ":")][0];'
GUARD='(.metadata.check // "") != "" and (tag("phase") | IN("feature", "harden", "infra"))'
SUBJECT='{feature: "feat", harden: "test", infra: "chore"}[tag("phase")]
  + "(" + (if tag("phase") == "infra" then "infra" else tag("feature") // .id end) + "): " + .title'
RENDER='{id, title, spec: (.metadata["long-description"] // ""), files: (.files | map("- " + .) | join("\n")),
    check: .metadata.check, reason: $reason, tail: $tail} as $v
  | ($tpl | split("@@failure@@\n")) as $p
  | ($p[0] + (if $reason == "" then "" else $p[1] // "" end))
  | gsub("\\{(?<k>id|title|spec|files|check|reason|tail)\\}"; $v[.k])'

log() {
  local line
  line="$(date '+%F %T') $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >>"$LOG"
}

die() {
  log "error: $*" >&2
  exit 1
}

milestone() { # log, plus a herdr notification when running inside herdr
  log "$*"
  if [ "${HERDR_ENV:-}" = 1 ] && command -v herdr >/dev/null 2>&1; then
    herdr notification show dag-loop --body "$*" >/dev/null 2>&1 || true
  fi
}

db() { # dagRobin, retried while its DB lock times out (exit 5)
  local rc
  while :; do
    rc=0
    dagRobin "$@" </dev/null || rc=$?
    [ "$rc" -eq 5 ] || return "$rc"
    sleep 1
  done
}

int() { case $2 in '' | *[!0-9]*) die "$1 must be a non-negative integer" ;; esac }

parse_args() {
  while [ $# -gt 0 ]; do
    case $1 in
      --host) HOST=${2:-} ;;
      --slots) SLOTS=${2:-} ;;
      --retries) RETRIES=${2:-} ;;
      --timeout) TIMEOUT=${2:-} ;;
      --max-cost) MAX_COST=${2:-} ;;
      *) die "usage: dag-loop.sh --host claude|codex|opencode|pi|omp|hermes|fake [--slots N] [--retries N] [--timeout SEC] [--max-cost USD]" ;;
    esac
    shift 2 || die "$1 needs a value"
  done
  int --slots "$SLOTS"
  int --retries "$RETRIES"
  int --timeout "$TIMEOUT"
  [ "$SLOTS" -ge 1 ] || die "--slots must be >= 1"
  case $HOST in
    fake) ;;
    claude | codex | opencode | pi | omp | hermes) command -v "$HOST" >/dev/null || die "$HOST not found on PATH" ;;
    *) die "--host must be one of claude|codex|opencode|pi|omp|hermes|fake" ;;
  esac
}

version_ok() { dagRobin --version 2>/dev/null | awk '{ split($2, v, ".") } END { exit !(v[1] + 0 > 0 || v[2] + 0 >= 2) }'; }

check_tools() {
  command -v jq >/dev/null || die "jq not found on PATH"
  command -v dagRobin >/dev/null || die "dagRobin not found on PATH"
  version_ok || die "dagRobin >= 0.2.0 required (found: $(dagRobin --version 2>/dev/null || echo none))"
  [ -r "$TEMPLATE" ] || die "worker prompt missing: $TEMPLATE"
}

resolve_db() {
  local db
  db=$(dagRobin which-db) || die "dagRobin which-db failed"
  case $db in /*) ;; *) db="$PWD/$db" ;; esac
  [ "$db" != "$HOME/.local/share/dagRobin/dagrobin.db" ] ||
    die "refusing the global dagRobin DB ($db): run 'dagRobin init' in the repo or export DAGROBIN_DB"
  [ -e "$db" ] || die "no dagRobin DB at $db"
  export DAGROBIN_DB="$db"
}

prepare_repo() {
  local gitdir exclude
  gitdir=$(git rev-parse --absolute-git-dir)
  exclude=$(git rev-parse --git-path info/exclude)
  mkdir -p "$(dirname "$exclude")"
  grep -qxF .worktrees/ "$exclude" 2>/dev/null || echo .worktrees/ >>"$exclude"
  git rev-parse -q --verify HEAD >/dev/null || die "repository has no commits"
  # Untracked files are ignored: merges and resets never touch them, and checks leave build output behind.
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "working tree has uncommitted changes"
  LOCK="$gitdir/dag-loop.lock" LOG="$gitdir/dag-loop.log" STATE="$gitdir/dag-loop.d"
  [ ! -d "$LOCK" ] || die "$LOCK exists: another dag-loop is merging, or a killed run left it (rmdir it)"
  READY="$STATE/ready.json"
  rm -rf "$STATE"
  mkdir -p "$STATE"
}

preflight() {
  check_tools
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repository"
  resolve_db
  cd "$ROOT"
  prepare_repo
}

task_q() { # id filter [jq options...]: evaluate filter on one task of the current ready snapshot
  local id=$1 filter=$2
  shift 2
  jq -r "$@" --arg id "$id" "$JQ_DEFS .[] | select(.id == \$id) | $filter" "$READY"
}

pick() { # up to SLOTS untried ready ids with pairwise-disjoint files, highest priority first
  jq -r --argjson n "$SLOTS" --arg tried "$TRIED" '
    ($tried | split(" ")) as $t
    | map(select(.id | IN($t[]) | not)) | sort_by(.priority, .id)
    | reduce .[] as $x ({ids: [], files: []};
        if (.ids | length) < $n and ($x.files - .files) == $x.files
        then .ids += [$x.id] | .files += $x.files else . end)
    | .ids[]' "$READY"
}

fail() { # id reason [output-name]: record why the attempt failed and the output tail the next prompt shows
  REASON=$2
  : >"$STATE/$1.tail"
  [ -z "${3:-}" ] || tail -n 20 "$STATE/$1.$3.out" >"$STATE/$1.tail"
  [ -s "$STATE/$1.tail" ] || echo "(no output)" >"$STATE/$1.tail"
}

drop_worktree() {
  local wt="$ROOT/.worktrees/$1"
  git worktree remove --force "$wt" >/dev/null 2>&1 || {
    rm -rf "$wt"
    git worktree prune
  }
  git branch -D "dagloop/$1" >/dev/null 2>&1 || true
}

fresh_worktree() { # id base
  drop_worktree "$1"
  git worktree add -q -b "dagloop/$1" "$ROOT/.worktrees/$1" "$2" >/dev/null 2>&1
}

stop_tree() {
  pkill -TERM -P "$1" 2>/dev/null || true
  kill -TERM "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

run_timed() { # id worktree → host exit code, 124 on timeout
  local pid start=$SECONDS
  run_host "$HOST" "$2" "$STATE/$1.prompt" "$MAX_COST" </dev/null >"$STATE/$1.host.out" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then
      stop_tree "$pid"
      return 124
    fi
    sleep 1
  done
  wait "$pid"
}

with_lock() {
  local rc=0
  until mkdir "$LOCK" 2>/dev/null; do sleep 1; done
  "$@" || rc=$?
  rmdir "$LOCK"
  return "$rc"
}

# shellcheck disable=SC2329 # called by merge_verify, which runs through with_lock
step() { # id reason cmd...: run cmd in the main tree; on failure reset it to PRE
  "${@:3}" >"$STATE/$1.merge.out" 2>&1 && return 0
  git reset -q --hard "$PRE"
  fail "$1" "$2" merge
  return 1
}

# shellcheck disable=SC2329 # called through with_lock
merge_verify() { # id; caller holds the lock
  local id=$1
  PRE=$(git rev-parse HEAD)
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    fail "$id" main-tree-dirty
    return 2
  fi
  step "$id" merge-conflict git merge --squash "dagloop/$id" &&
    step "$id" commit-failed git commit -q -m "$(task_q "$id" "$SUBJECT")" &&
    step "$id" verify-failed db verify "$id" &&
    log "$id merged as $(git rev-parse --short HEAD)"
}

attempt() { # id → 0 merged and verified, 1 task failure, 2 host or environment fault; sets REASON
  local id=$1 base host_rc=0 commits wt="$ROOT/.worktrees/$1"
  base=$(git rev-parse HEAD)
  fresh_worktree "$id" "$base" || { fail "$id" worktree-failed; return 1; }
  task_q "$id" "$RENDER" --rawfile tpl "$TEMPLATE" --rawfile tail "$STATE/$id.tail" --arg reason "$REASON" \
    >"$STATE/$id.prompt" || { fail "$id" render-failed; return 1; }
  run_timed "$id" "$wt" || host_rc=$?
  if [ "$host_rc" -eq 124 ]; then fail "$id" timeout host; return 2; fi
  commits=$(git rev-list --count "$base..dagloop/$id" 2>/dev/null || echo 0)
  if [ "$commits" -eq 0 ] && [ "$host_rc" -ne 0 ]; then fail "$id" crash host; return 2; fi
  if [ "$commits" -eq 0 ]; then fail "$id" no-commit; return 1; fi
  (cd "$wt" && exec sh -c "$(task_q "$id" .metadata.check)") </dev/null >"$STATE/$id.check.out" 2>&1 ||
    { echo "check exited $?" >>"$STATE/$id.check.out"; fail "$id" check-failed check; return 1; }
  with_lock merge_verify "$id"
}

block() {
  db update "$1" --status blocked --metadata "notes:dag-loop $REASON" >/dev/null || log "$1 could not be marked blocked"
  milestone "$1 blocked: $REASON"
}

release() {
  db update "$1" --status pending >/dev/null || log "$1 could not be returned to pending"
  log "$1 returned to pending after $REASON (host or environment fault, not a task verdict)"
}

work() { # id agent; runs as a background job
  local id=$1 n=0 rc=0
  : >"$STATE/$id.tail"
  if ! task_q "$id" "$GUARD" -e >/dev/null; then
    REASON="bad-contract: needs metadata.check and a phase:feature|harden|infra tag"
    block "$id"
    return 0
  fi
  while [ "$n" -le "$RETRIES" ]; do
    n=$((n + 1))
    log "$id attempt $n/$((RETRIES + 1)) by $2"
    rc=0
    attempt "$id" || rc=$?
    drop_worktree "$id"
    if [ "$rc" -eq 0 ]; then milestone "$id done"; return 0; fi
    log "$id attempt $n failed: $REASON"
  done
  if [ "$rc" -eq 2 ]; then release "$id"; else block "$id"; fi
}

claim() {
  local rc=0
  db claim "$1" -a "$2" >/dev/null 2>&1 || rc=$?
  case $rc in
    0) return 0 ;;
    3 | 4) log "$1 skipped: claimed elsewhere or deps not done (claim exit $rc)"; return 1 ;;
    *) die "dagRobin claim $1 failed (exit $rc)" ;;
  esac
}

run_round() {
  local id slot=0 entry
  for id in "$@"; do
    TRIED="$TRIED $id"
    slot=$((slot + 1))
    claim "$id" "dagloop-$HOST-$slot" || continue
    work "$id" "dagloop-$HOST-$slot" &
    INFLIGHT="$INFLIGHT $!:$id"
  done
  for entry in $INFLIGHT; do wait "${entry%%:*}" || true; done
  INFLIGHT=""
}

# shellcheck disable=SC2329 # EXIT trap
on_exit() { # only an interrupted or failed round leaves INFLIGHT set
  local entry
  for entry in $INFLIGHT; do stop_tree "${entry%%:*}"; done
  for entry in $INFLIGHT; do
    db update "${entry#*:}" --status pending >/dev/null 2>&1 || true
    drop_worktree "${entry#*:}"
    log "${entry#*:} returned to pending (driver stopped)"
  done
  [ -z "$INFLIGHT" ] || rmdir "$LOCK" 2>/dev/null || true
}

finish() {
  local open ready
  open=$(db list --format json | jq '[.[] | select(.status != "Done" and (.archived | not))] | length') ||
    die "dagRobin list failed"
  if [ "$open" -eq 0 ]; then milestone "all tasks done"; exit 0; fi
  ready=$(db ready --format json | jq 'length') || die "dagRobin ready failed"
  if [ "$ready" -eq 0 ]; then milestone "stopped: $open open task(s), none ready (blocked or waiting on deps)"; exit 3; fi
  milestone "stopped: $ready ready task(s) not done this run (host crash/timeout)"
  exit 1
}

main() {
  local ids
  parse_args "$@"
  preflight
  trap on_exit EXIT
  trap 'exit 130' INT TERM
  log "start host=$HOST slots=$SLOTS retries=$RETRIES timeout=${TIMEOUT}s db=$DAGROBIN_DB"
  while :; do
    db ready --format json >"$READY" || die "dagRobin ready failed"
    ids=$(pick) || die "cannot parse dagRobin ready output"
    [ -n "$ids" ] || break
    # shellcheck disable=SC2086 # task ids contain no whitespace
    run_round $ids
  done
  finish
}

main "$@"
