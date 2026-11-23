#!/usr/bin/env bash
# Sourced by dag-loop.sh. run_host replaces the calling shell with the host CLI, so call it with & or in a subshell.
# The prompt goes in as a positional argument; --help of claude 2.1, codex exec, opencode run, omp 18 and hermes -z
# all accept it. Every host runs with permissions bypassed, which is the user's decision to make.

run_host() { # host worktree prompt-file max-cost
  local host=$1 wt=$2 cost=$4 prompt
  prompt=$(cat "$3") || return 1
  cd "$wt" || return 1
  unset CLAUDECODE
  [ "${DAGLOOP_KEEP_API_KEY:-}" = 1 ] || unset ANTHROPIC_API_KEY
  case $host in
    claude) exec claude -p --setting-sources project --dangerously-skip-permissions --max-budget-usd "$cost" "$prompt" ;;
    codex) exec codex exec -C "$wt" --dangerously-bypass-approvals-and-sandbox "$prompt" ;;
    opencode) exec opencode run --dir "$wt" --auto "$prompt" ;;
    # UNVERIFIED: pi is not installed here; -p and the positional prompt come from research section D only.
    pi) exec pi -p "$prompt" ;;
    omp) exec omp -p --cwd "$wt" --auto-approve --max-cost "$cost" "$prompt" ;;
    hermes) exec hermes -z "$prompt" ;;
    fake) exec sh -c "${DAGLOOP_FAKE_CMD:?DAGLOOP_FAKE_CMD is not set}" ;;
    *) echo "run_host: unknown host '$host'" >&2; return 1 ;;
  esac
}
