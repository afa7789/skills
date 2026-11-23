#!/usr/bin/env bash
# Install (or --uninstall) the dag-loop herdr plugin from this repo:
# links herdr/ as plugin `skills.dagloop` and adds three keybindings to herdr's config.toml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ID="skills.dagloop"
CONFIG="${HERDR_CONFIG:-$HOME/.config/herdr/config.toml}"
BEGIN="# >>> skills.dagloop keys (managed by scripts/herdr-install.sh) >>>"
END="# <<< skills.dagloop keys <<<"
KEYS='[[keys.command]]
key = "prefix+alt+w"
type = "plugin_action"
command = "skills.dagloop.watch"
description = "dag-loop: watch log"

[[keys.command]]
key = "prefix+alt+r"
type = "plugin_action"
command = "skills.dagloop.start"
description = "dag-loop: start (claude)"

[[keys.command]]
key = "prefix+alt+s"
type = "plugin_action"
command = "skills.dagloop.status"
description = "dagRobin: status"'

die() { echo "herdr-install: $*" >&2; exit 1; }

drop_keys() { # remove our managed block and trailing blank lines; everything else stays as is
    [ -f "$CONFIG" ] || return 0
    awk -v b="$BEGIN" -v e="$END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        skip { next }
        /^$/ { blanks++; next }
        { while (blanks > 0) { print ""; blanks-- } print }
    ' "$CONFIG" >"$CONFIG.tmp"
    mv "$CONFIG.tmp" "$CONFIG"
}

reload() { herdr server reload-config >/dev/null 2>&1 || echo "note: herdr server not running; keys load on next start"; }

install() {
    herdr plugin unlink "$PLUGIN_ID" >/dev/null 2>&1 || true
    herdr plugin link "$ROOT/herdr" >/dev/null || die "herdr plugin link failed"
    mkdir -p "$(dirname "$CONFIG")"
    touch "$CONFIG"
    cp "$CONFIG" "$CONFIG.bak-dagloop"
    drop_keys
    printf '\n%s\n%s\n%s\n' "$BEGIN" "$KEYS" "$END" >>"$CONFIG"
    if ! herdr config check; then
        cp "$CONFIG.bak-dagloop" "$CONFIG"
        die "config check failed (key clash?); keybindings not added, plugin still linked"
    fi
    reload
    herdr plugin list --plugin "$PLUGIN_ID"
    cat <<'EOF'

Installed. Inside herdr, in a pane at your project:
  prefix+alt+w  watch .git/dag-loop.log in a split
  prefix+alt+r  start dag-loop (--host claude) in a split
  prefix+alt+s  dagRobin status as a notification
Or: herdr plugin action invoke skills.dagloop.watch
dag-loop itself sends herdr notifications when a task is done or blocked and when it stops.
EOF
}

uninstall() {
    herdr plugin unlink "$PLUGIN_ID" >/dev/null 2>&1 || true
    drop_keys
    reload
    echo "Uninstalled $PLUGIN_ID."
}

command -v herdr >/dev/null || die "herdr not found on PATH"
command -v jq >/dev/null || die "jq not found on PATH (the plugin needs it)"
case "${1:-}" in
    "") install ;;
    --uninstall) uninstall ;;
    *) die "usage: herdr-install.sh [--uninstall]" ;;
esac
