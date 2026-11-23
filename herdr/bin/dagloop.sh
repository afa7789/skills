#!/bin/sh
# herdr plugin actions for dag-loop: watch | start | status.
# herdr runs actions with cwd = the plugin dir; the project is the focused pane's working directory.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)

notify() { herdr notification show dag-loop --body "$1" >/dev/null 2>&1 || true; }

project_dir() {
  herdr pane get "${HERDR_PANE_ID:?not running inside herdr}" |
    jq -r '.result.pane.foreground_cwd // .result.pane.cwd // empty'
}

driver() { # repo checkout first (plugin linked from the repo), then the synced copy
  for d in "$here/../skills/dag-loop/scripts/dag-loop.sh" "$HOME/.claude/skills/dag-loop/scripts/dag-loop.sh"; do
    if [ -f "$d" ]; then echo "$d"; return 0; fi
  done
  return 1
}

split_run() { # direction dir command
  pane=$(herdr pane split --pane "$HERDR_PANE_ID" --direction "$1" --cwd "$2" --no-focus | jq -r '.result.pane.pane_id')
  herdr pane run "$pane" "$3"
}

dir=$(project_dir)
[ -n "$dir" ] || { notify "focused pane has no working directory"; exit 1; }

case "${1:-}" in
  watch)
    # shellcheck disable=SC2016 # expands in the new pane's shell, inside the project
    split_run right "$dir" 'tail -n 40 -F "$(git rev-parse --git-common-dir)/dag-loop.log"' ;;
  start)
    d=$(driver) || { notify "dag-loop.sh not found: run scripts/sync-skills.sh"; exit 1; }
    split_run down "$dir" "bash '$d' --host ${DAGLOOP_HOST:-claude}" ;;
  status)
    notify "$(cd "$dir" && dagRobin status 2>&1 | head -3 | tr '\n' ' ')" ;;
  *)
    echo "usage: dagloop.sh watch|start|status" >&2
    exit 2 ;;
esac
