#!/usr/bin/env bash
# gate.sh — the repo's binary done-check. Exit 0 = safe to push.
# Runs: shellcheck, the sync suite, every skills/*/tests/*.test.sh, line budgets.
# Browser e2e (skills/*/tests/*.e2e.mjs) is NOT run here: it needs npx + Chromium.
set -euo pipefail
shopt -s nullglob

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ALWAYS_LOADED_MAX=80
SKILL_MAX=100
# Kept from v1 as-is; new skills must fit SKILL_MAX.
OVER_BUDGET_OK="estimator peer-review solidity-review solidity-complex-audit ste-docs"

failures=0
step() { printf '\n== %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; failures=$((failures + 1)); }

step "shellcheck"
# shellcheck disable=SC2046  # word-splitting the file list is intended
shellcheck scripts/*.sh skills/*/scripts/*.sh skills/*/tests/*.sh herdr/bin/*.sh || bad "shellcheck"
python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' herdr/herdr-plugin.toml || bad "herdr/herdr-plugin.toml is not valid TOML"

step "sync suite"
bash scripts/test-sync-skills.sh >/dev/null 2>&1 || bad "scripts/test-sync-skills.sh (run it for details)"

for t in skills/*/tests/*.test.sh; do
    step "$t"
    bash "$t" >/dev/null 2>&1 || bad "$t (run it for details)"
done

step "budgets"
lines="$(cat global/CLAUDE.md rules/*.md | wc -l | tr -d ' ')"
[ "$lines" -le "$ALWAYS_LOADED_MAX" ] || bad "always-loaded rules: $lines lines > $ALWAYS_LOADED_MAX"
for f in skills/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    case " $OVER_BUDGET_OK " in *" $name "*) continue ;; esac
    n="$(wc -l < "$f" | tr -d ' ')"
    [ "$n" -le "$SKILL_MAX" ] || bad "$f: $n lines > $SKILL_MAX"
done
printf '  always-loaded: %s/%s lines\n' "$lines" "$ALWAYS_LOADED_MAX"

printf '\n'
if [ "$failures" -gt 0 ]; then
    printf 'GATE FAIL (%s)\n' "$failures"
    exit 1
fi
printf 'GATE PASS\n'
