#!/usr/bin/env bash
# Run: bash skills/fdd/tests/check-dag.test.sh
set -euo pipefail

SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/check-dag.sh"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
FAILED=0

# task ID TAGS [CHECK] [FILES] [SPEC] — pass "" to blank a field.
task() {
  cat <<EOF
- id: $1
  title: $1
  tags: [$2]
  files: [${4-src/$1.rs}]
  metadata:
    long-description: ${5-spec for $1}
    check: ${3-true}
EOF
}

feat() { task "$1" "feature:F-001, phase:feature"; }

# Takes YAML as an argument: piping into load would run it in a subshell and lose DAGROBIN_DB.
load() {
  DAGROBIN_DB="$(mktemp -d "$ROOT/db.XXXXXX")/db"
  export DAGROBIN_DB
  printf '%s\n' "$1" >"$DAGROBIN_DB.yaml"
  dagRobin import "$DAGROBIN_DB.yaml" >/dev/null
}

# expect NAME EXIT TEXT [ARGS...]
expect() {
  local name=$1 want=$2 text=$3 out rc
  shift 3
  out=$("$BASH" "$SUT" "$@" 2>&1) && rc=0 || rc=$?
  case "$rc:$out" in
    "$want:"*"$text"*) echo "PASS $name" ;;
    *) FAILED=1; printf 'FAIL %s (exit %s, want %s + "%s")\n%s\n' "$name" "$rc" "$want" "$text" "$out" ;;
  esac
}

many() { local i; for i in $(seq 1 "$1"); do feat "f$i"; done; }

valid_yaml() {
  feat f001-login
  task i001-workspace "feature:infra, phase:infra" 'cargo build -q'
  cat <<'EOF'
- id: f002-logout
  title: Logout
  deps: [f001-login]
  files: [src/auth/logout.rs]
  tags: [feature:F-002, phase:feature]
  metadata:
    long-description: |
      Logout clears the session.
    check: |
      cargo build -q &&
      cargo run -q -- logout | grep -q OK
EOF
}

valid_round() {
  load "$(valid_yaml)"
  expect "valid round" 0 "check-dag: OK 3 active"
}

field_rules() {
  load "$(task t1 "feature:F-001, phase:feature" "")"
  expect "missing check" 1 "t1: missing metadata.check"
  load "$(task t1 "feature:F-001, phase:feature" true "")"
  expect "empty files" 1 "t1: empty files"
  load "$(task t1 "feature:F-001, phase:feature" true src/a.rs "")"
  expect "missing long-description" 1 "t1: missing metadata.long-description"
}

tag_rules() {
  load "$(task t1 "phase:feature")"
  expect "no feature tag" 1 "t1: needs exactly one feature: tag"
  load "$(task t1 "feature:F-001, feature:F-002, phase:feature")"
  expect "two feature tags" 1 "t1: needs exactly one feature: tag"
  load "$(task t1 "feature:F-001")"
  expect "no phase tag" 1 "t1: needs exactly one phase: tag"
  load "$(task t1 "feature:F-001, phase:feature, phase:infra")"
  expect "two phase tags" 1 "t1: needs exactly one phase: tag"
  load "$(task t1 "feature:F-001, phase:polish")"
  expect "bad phase value" 1 "t1: needs exactly one phase: tag"
}

harden_rules() {
  load "$(feat f1; task h1 "feature:F-001, phase:harden")"
  expect "harden before features Done" 1 "h1: phase:harden while 1 phase:feature task(s) not Done"
  dagRobin verify f1 >/dev/null
  expect "harden after features Done" 0 "check-dag: OK 2 active, 1 non-Done"
}

round_rules() {
  load "$(feat f1; task bad "phase:feature" "")"
  dagRobin archive bad >/dev/null
  expect "archived offender ignored" 0 "check-dag: OK 1 active"
  load "$(many 25)"
  expect "25 non-Done" 0 "check-dag: OK 25 active"
  local good=$DAGROBIN_DB
  load "$(many 26)"
  expect "26 non-Done" 1 "round: 26 non-Done tasks > max 25"
  expect "--max override" 0 "(max 30)" --max 30
  expect "--db wins over DAGROBIN_DB" 0 "check-dag: OK 25 active" --db "$good"
}

valid_round
field_rules
tag_rules
harden_rules
round_rules
exit "$FAILED"
