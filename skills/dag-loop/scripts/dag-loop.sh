#!/usr/bin/env bash
# dag-loop: run dagRobin's ready tasks through a headless coding agent, one git worktree per batch.
# Usage: dag-loop.sh --host claude|codex|opencode|pi|omp|hermes|agy|fake [--slots 1] [--batch all|N] [--retries 2] [--timeout 1800] [--max-cost 2]
# Exit: 0 all tasks done; 3 only blocked/unready tasks remain; 1 error (or ready tasks left after host crash/timeout).
# shellcheck disable=SC2016 # single-quoted strings are jq programs
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR
# shellcheck source=adapters.sh
. "$HERE/adapters.sh"
TEMPLATE="$HERE/../prompts/worker.md"

HOST="" SLOTS=1 BATCH="all" BATCH_MAX=0 RETRIES=2 TIMEOUT=1800 MAX_COST=2
ROOT="" LOCK="" STATE="" READY="" LOG=/dev/null
TRIED="" INFLIGHT="" REASON="" PRE="" ROUND=0

JQ_DEFS='def tag($k): [.tags[]? | select(startswith($k + ":")) | ltrimstr($k + ":")][0];'
GUARD='(.metadata.check // "") != "" and (tag("phase") | IN("feature", "harden", "infra"))'
SUBJECT='{feature: "feat", harden: "test", infra: "chore"}[tag("phase")]
  + "(" + (if tag("phase") == "infra" then "infra" else tag("feature") // .id end) + "): " + .title'
RENDER_BATCH='
  ($ids | split(" ")) as $wanted
  | map(select(.id | IN($wanted[])))
  | (if length == 1 then "task \(.[0].id): \(.[0].title)"
     else "a batch of \(length) tasks (\([.[].id] | join(", ")))" end) as $scope
  | (map(
      "## Task \(.id): \(.title)\n\n### Spec\n\n\(.metadata["long-description"] // "")\n\n### Files\n\n\((.files // []) | map("- " + .) | join("\n"))\n\n### Check\n\n```sh\n\(.metadata.check)\n```"
    ) | join("\n\n")) as $tasks
  | {scope: $scope, tasks: $tasks, reason: $reason, tail: $tail} as $v
  | ($tpl | split("@@failure@@\n")) as $p
  | ($p[0] + (if $reason == "" then "" else $p[1] // "" end))
  | gsub("\\{(?<k>scope|tasks|reason|tail)\\}"; $v[.k])'
COMMIT_MSG='
  ($ids | split(" ")) as $wanted
  | map(select(.id | IN($wanted[]))) as $items
  | if ($items | length) == 1 then
      $items[0] | '"$SUBJECT"'
    else
      ([$items[] | tag("phase")] | unique) as $phases
      | (if ($phases | length) == 1 then {feature: "feat", harden: "test", infra: "chore"}[$phases[0]] else "feat" end) as $kind
      | ([$items[] | if tag("phase") == "infra" then "infra" else tag("feature") // .id end] | unique) as $feats
      | "\($kind)(\($feats | join(","))): \($items | length) tasks\n\n"
        + ([$items[] | "- " + ('"$SUBJECT"')] | join("\n"))
    end'

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
      --batch) BATCH=${2:-} ;;
      --retries) RETRIES=${2:-} ;;
      --timeout) TIMEOUT=${2:-} ;;
      --max-cost) MAX_COST=${2:-} ;;
      *) die "usage: dag-loop.sh --host claude|codex|opencode|pi|omp|hermes|agy|fake [--slots N] [--batch all|N] [--retries N] [--timeout SEC] [--max-cost USD]" ;;
    esac
    shift 2 || die "$1 needs a value"
  done
  int --slots "$SLOTS"
  int --retries "$RETRIES"
  int --timeout "$TIMEOUT"
  [ "$SLOTS" -ge 1 ] || die "--slots must be >= 1"
  if [ "$BATCH" = "all" ]; then
    BATCH_MAX=0
  else
    int --batch "$BATCH"
    [ "$BATCH" -ge 1 ] || die "--batch must be 'all' or >= 1"
    BATCH_MAX=$BATCH
  fi
  case $HOST in
    fake) ;;
    claude | codex | opencode | pi | omp | hermes | agy) command -v "$HOST" >/dev/null || die "$HOST not found on PATH" ;;
    *) die "--host must be one of claude|codex|opencode|pi|omp|hermes|agy|fake" ;;
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

# Partition untried ready tasks into up to SLOTS batches (each <= BATCH_MAX, 0 = unlimited),
# keeping cross-slot files disjoint while allowing overlapping files in the same single-agent batch.
pick() {
  jq -r --argjson slots "$SLOTS" --argjson bmax "$BATCH_MAX" --arg tried "$TRIED" '
    def overlaps($a; $b): (($a - $b) | length) < ($a | length);
    def room($batch): ($bmax == 0) or (($batch.ids | length) < $bmax);
    ($tried | split(" ")) as $t
    | map(select(.id | IN($t[]) | not)) | sort_by(.priority, .id)
    | reduce .[] as $x ([];
        ($x.files // []) as $xf
        | [range(0; length) as $i | select(overlaps(.[$i].files; $xf)) | $i] as $hits
        | if ($hits | length) > 1 then
            .
          elif ($hits | length) == 1 then
            $hits[0] as $k
            | if room(.[$k]) then
                .[$k].ids += [$x.id] | .[$k].files = ((.[$k].files + $xf) | unique)
              else . end
          elif length < $slots then
            . + [{ids: [$x.id], files: ($xf | unique)}]
          else
            ([to_entries[] | select(room(.value))] | sort_by([(.value.ids | length), .key]) | .[0].key) as $k
            | if $k != null then
                .[$k].ids += [$x.id] | .[$k].files = ((.[$k].files + $xf) | unique)
              else . end
          end
      )
    | .[] | .ids | join(" ")' "$READY"
}

fail() { # key reason [output-name]: record why the attempt failed and the output tail the next prompt shows
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

fresh_worktree() { # key base
  drop_worktree "$1"
  git worktree add -q -b "dagloop/$1" "$ROOT/.worktrees/$1" "$2" >/dev/null 2>&1
}

stop_tree() {
  pkill -TERM -P "$1" 2>/dev/null || true
  kill -TERM "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

run_timed() { # key worktree tasks-csv → host exit code, 124 on timeout
  local pid start=$SECONDS
  DAGLOOP_TASKS="$3" run_host "$HOST" "$2" "$STATE/$1.prompt" "$MAX_COST" </dev/null >"$STATE/$1.host.out" 2>&1 &
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
step() { # key reason cmd...: run cmd in the main tree; on failure reset it to PRE
  "${@:3}" >"$STATE/$1.merge.out" 2>&1 && return 0
  git reset -q --hard "$PRE"
  fail "$1" "$2" merge
  return 1
}

# shellcheck disable=SC2329 # called by merge_verify via step
verify_all() { # ids...
  local id
  for id in "$@"; do
    db verify "$id" || return 1
  done
}

# shellcheck disable=SC2329 # called through with_lock
merge_verify() { # key ids-space-sep; caller holds the lock
  local key=$1 ids_str=$2
  local -a ids
  read -r -a ids <<<"$ids_str"
  PRE=$(git rev-parse HEAD)
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    fail "$key" main-tree-dirty
    return 2
  fi
  jq -r --arg ids "$ids_str" "$JQ_DEFS $COMMIT_MSG" "$READY" >"$STATE/$key.msg"
  step "$key" merge-conflict git merge --squash "dagloop/$key" &&
    step "$key" commit-failed git commit -q -F "$STATE/$key.msg" &&
    step "$key" verify-failed verify_all "${ids[@]}" &&
    log "$key merged as $(git rev-parse --short HEAD)"
}

check_batch() { # key wt ids...; writes passing/failing ids to STATE/$key.{passed,failed}
  local key=$1 wt=$2 id rc
  shift 2
  : >"$STATE/$key.check.out"
  : >"$STATE/$key.passed"
  : >"$STATE/$key.failed"
  for id in "$@"; do
    rc=0
    (cd "$wt" && exec sh -c "$(task_q "$id" .metadata.check)") </dev/null >"$STATE/$key.$id.check.out" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      printf '%s\n' "$id" >>"$STATE/$key.passed"
    else
      printf '%s\n' "$id" >>"$STATE/$key.failed"
      {
        printf '=== check failed: %s (exit %s) ===\n' "$id" "$rc"
        cat "$STATE/$key.$id.check.out"
      } >>"$STATE/$key.check.out"
    fi
  done
  [ ! -s "$STATE/$key.failed" ]
}

attempt() { # key ids-space-sep → 0 merged and verified, 1 task failure, 2 host or environment fault; sets REASON
  local key=$1 ids_str=$2 base host_rc=0 commits wt="$ROOT/.worktrees/$1"
  local -a ids
  read -r -a ids <<<"$ids_str"
  base=$(git rev-parse HEAD)
  fresh_worktree "$key" "$base" || { fail "$key" worktree-failed; return 1; }
  jq -r --arg ids "$ids_str" --rawfile tpl "$TEMPLATE" --rawfile tail "$STATE/$key.tail" --arg reason "$REASON" \
    "$RENDER_BATCH" "$READY" >"$STATE/$key.prompt" || { fail "$key" render-failed; return 1; }
  run_timed "$key" "$wt" "$ids_str" || host_rc=$?
  if [ "$host_rc" -eq 124 ]; then fail "$key" timeout host; return 2; fi
  commits=$(git rev-list --count "$base..dagloop/$key" 2>/dev/null || echo 0)
  if [ "$commits" -eq 0 ] && [ "$host_rc" -ne 0 ]; then fail "$key" crash host; return 2; fi
  if [ "$commits" -eq 0 ]; then fail "$key" no-commit; return 1; fi
  check_batch "$key" "$wt" "${ids[@]}" || { fail "$key" check-failed check; return 1; }
  with_lock merge_verify "$key" "$ids_str"
}

block() {
  db update "$1" --status blocked --metadata "notes:dag-loop $REASON" >/dev/null || log "$1 could not be marked blocked"
  milestone "$1 blocked: $REASON"
}

release() {
  db update "$1" --status pending >/dev/null || log "$1 could not be returned to pending"
  log "$1 returned to pending after $REASON (host or environment fault, not a task verdict)"
}

requeue() {
  db update "$1" --status pending >/dev/null || log "$1 could not be returned to pending"
  printf '%s\n' "$1" >>"$STATE/$2.requeue"
  log "$1 returned to pending (passed check, sibling failed in batch $2)"
}

work() { # key agent ids-space-sep; runs as a background job
  local key=$1 agent=$2 ids_str=$3 n=0 rc=0 id
  local -a ids
  read -r -a ids <<<"$ids_str"
  : >"$STATE/$key.tail"
  while [ "$n" -le "$RETRIES" ]; do
    n=$((n + 1))
    log "$key attempt $n/$((RETRIES + 1)) by $agent (tasks: $ids_str)"
    rc=0
    attempt "$key" "$ids_str" || rc=$?
    drop_worktree "$key"
    if [ "$rc" -eq 0 ]; then
      for id in "${ids[@]}"; do milestone "$id done"; done
      return 0
    fi
    log "$key attempt $n failed: $REASON"
  done
  if [ "$rc" -eq 2 ]; then
    for id in "${ids[@]}"; do release "$id"; done
  elif [ "${#ids[@]}" -gt 1 ] && [ "$REASON" = "check-failed" ] && [ -s "$STATE/$key.passed" ] && [ -s "$STATE/$key.failed" ]; then
    while IFS= read -r id; do [ -n "$id" ] && block "$id"; done <"$STATE/$key.failed"
    while IFS= read -r id; do [ -n "$id" ] && requeue "$id" "$key"; done <"$STATE/$key.passed"
  else
    for id in "${ids[@]}"; do block "$id"; done
  fi
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

drop_from_tried() { # id
  local out="" item
  for item in $TRIED; do
    [ "$item" = "$1" ] || out="$out $item"
  done
  TRIED="$out"
}

run_round() { # lines of space-separated task ids on stdin
  local line slot=0 id key entry agent claimed_str
  local -a batch_ids claimed_ids
  ROUND=$((ROUND + 1))
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    slot=$((slot + 1))
    agent="dagloop-$HOST-$slot"
    read -r -a batch_ids <<<"$line"
    claimed_ids=()
    for id in "${batch_ids[@]}"; do
      TRIED="$TRIED $id"
      if ! task_q "$id" "$GUARD" -e >/dev/null; then
        REASON="bad-contract: needs metadata.check and a phase:feature|harden|infra tag"
        block "$id"
        continue
      fi
      claim "$id" "$agent" && claimed_ids+=("$id")
    done
    [ "${#claimed_ids[@]}" -gt 0 ] || continue
    if [ "${#claimed_ids[@]}" -eq 1 ]; then
      key="${claimed_ids[0]}"
    else
      key="batch-$ROUND-$slot"
    fi
    claimed_str="${claimed_ids[*]}"
    work "$key" "$agent" "$claimed_str" &
    INFLIGHT="$INFLIGHT $!:$key:${claimed_str// /,}"
  done
  for entry in $INFLIGHT; do wait "${entry%%:*}" || true; done
  for entry in $INFLIGHT; do
    key="${entry#*:}"
    key="${key%%:*}"
    if [ -s "$STATE/$key.requeue" ]; then
      while IFS= read -r id; do [ -n "$id" ] && drop_from_tried "$id"; done <"$STATE/$key.requeue"
    fi
  done
  INFLIGHT=""
}

# shellcheck disable=SC2329 # EXIT trap
on_exit() { # only an interrupted or failed round leaves INFLIGHT set
  local entry rest key ids_csv id
  for entry in $INFLIGHT; do stop_tree "${entry%%:*}"; done
  for entry in $INFLIGHT; do
    rest="${entry#*:}"
    key="${rest%%:*}"
    ids_csv="${rest#*:}"
    drop_worktree "$key"
    IFS=',' read -r -a _ids <<<"$ids_csv"
    for id in "${_ids[@]}"; do
      db update "$id" --status pending >/dev/null 2>&1 || true
      log "$id returned to pending (driver stopped)"
    done
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
  local batches
  parse_args "$@"
  preflight
  trap on_exit EXIT
  trap 'exit 130' INT TERM
  log "start host=$HOST slots=$SLOTS batch=$BATCH retries=$RETRIES timeout=${TIMEOUT}s db=$DAGROBIN_DB"
  while :; do
    db ready --format json >"$READY" || die "dagRobin ready failed"
    batches=$(pick) || die "cannot parse dagRobin ready output"
    [ -n "$batches" ] || break
    run_round <<<"$batches"
  done
  finish
}

main "$@"
