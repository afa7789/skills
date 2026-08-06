#!/usr/bin/env bash
# shellcheck shell=bash
#
# sync-skills.sh — Single source of truth for the entire skills repo.
#
# This one script syncs skills/, agents/, rules/, resources/, global/ to:
#   - Claude Code      (~/.claude/)
#   - OpenCode         (~/.config/opencode/)
#   - Codex CLI        (~/.codex/)
#   - Hermes Agent     (~/.hermes/)
#   - Pi coding agent  (~/.pi/agent/)
#
# Tools that aren't installed locally are skipped silently (no auto-install,
# no errors). Install manually if you want them synced.
#
# What it does for each installed tool:
#   Claude   — verbatim copy of agents, skills, rules, resources
#   OpenCode — agents translated (Claude CSV tools: → permission: deny; mode:
#              preserved, model: dropped), plus opencode.json managed keys
#   Codex    — skills only, plus approval_policy/sandbox_mode in config.toml
#   Hermes   — categorized skills (5 subdirs), agents converted to slash
#              commands, SOUL.md composed (with .bak), skill-bundles
#              installed, approvals/command_allowlist merged into config.yaml
#   Pi       — skills verbatim (same SKILL.md format), agents translated to
#              Pi's lowercase tool names, global AGENTS.md composed. Pi has no
#              permission surface, so --mode does not apply to it.
#
# Managed settings are MERGED, never overwritten: every key this script does
# not own is preserved byte-for-byte. A config that fails to parse is backed
# up and left alone rather than clobbered.
#
# Idempotent via SHA-256 checksums cached in ~/.afasync/state.json. Each step
# is skipped when its inputs match the cached state.
#
# Usage:
#   scripts/sync-skills.sh [options]
#
# Options:
#   --mode=MODE            trust mode for perms: strict|smart|yolo (default smart)
#   --only=T[,T...]        limit to some targets: claude,opencode,codex,hermes,pi
#   --skip-sync            skip content sync (only update managed settings)
#   --skip-permissions     skip managed settings (only sync content)
#   --force                ignore cached checksums; redo everything
#   --status               dry run + report; no writes
#   --reset                clear cached state, then run
#   -h, --help             show this
#
# A single positional argument (historically `paths.txt`) is accepted and
# ignored, so older documented invocations keep working. Destinations are
# fixed and no longer read from a file.
#
# Environment:
#   HERMES_HOME                 override ~/.hermes (default ~/.hermes)
#   PI_HOME                     override ~/.pi (default ~/.pi)
#   HERMES_ADAPTER_PROJECT_DIR  if set with HERMES_ADAPTER_WRITE_AGENTS=1,
#                               writes <that dir>/AGENTS.md with our
#                               engineering + rtk + dagrobin rules plus
#                               any stack-specific rule (auto-detected).
#   HERMES_ADAPTER_FORCE        overwrite an existing AGENTS.md
#   AFSYNC_STATE                override state file path
#                               (default ~/.afasync/state.json)
#   AFSYNC_QUIET                set to 1 for compact output (errors still shown)
#   AFSYNC_BACKUP_KEEP          how many .bak-* to retain per file (default 5)

set -euo pipefail
shopt -s nullglob

# =============================================================================
# 1. Constants
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE_FILE="${AFSYNC_STATE:-$HOME/.afasync/state.json}"
BACKUP_KEEP="${AFSYNC_BACKUP_KEEP:-5}"

# Destination roots. Hardcoded on purpose — paths.txt is gone, every platform
# here is a known, fixed target.
CLAUDE_HOME="$HOME/.claude"
OPENCODE_HOME="$HOME/.config/opencode"
CODEX_HOME="$HOME/.codex"
PI_HOME="${PI_HOME:-$HOME/.pi}"
PI_AGENT_HOME="$PI_HOME/agent"

# Per-platform managed settings files (inside each tool's own config).
OPENCODE_CONFIG="$OPENCODE_HOME/opencode.json"
CODEX_CONFIG="$CODEX_HOME/config.toml"
HERMES_CONFIG="$HERMES_HOME/config.yaml"

ALL_TOOLS="claude opencode codex hermes pi"

# Skills that used to be generated from agents/*.md and must be pruned from
# every skills root. Declared once — all targets consume this list.
STALE_AGENT_SKILLS="orchestrator architect builder qa-evaluator code-reviewer project-manager summarizer-auditor"

# Hermes groups skills into category subdirs. One declarative table; anything
# absent lands at the top level and is reported so the drift stays visible.
HERMES_CATEGORIES='
better-accessibility:design
better-colors:design
better-interface:design
better-layout:design
better-typography:design
better-ui:design
better-writing:design
differ-helper:code-quality
frontend-audit:code-quality
pr-review-pipeline:code-quality
peer-review:code-quality
solidity-review:code-quality
estimator:planning
multi-agent-loop:planning
prompt-refiner:planning
reader:docs
ste-docs:docs
orchestrator:workflow
architect:workflow
project-manager:workflow
builder:workflow
qa-evaluator:workflow
code-reviewer:workflow
summarizer-auditor:workflow
'

# Default arg values (overridden by flags).
MODE="smart"
ONLY=""
SKIP_SYNC=0
SKIP_PERMISSIONS=0
FORCE=0
DRY_RUN=0
RESET=0

# =============================================================================
# 2. Output helpers
# =============================================================================
# say/ok/skip/do_/note are progress chatter and honour AFSYNC_QUIET.
# warn/fail are diagnostics: always on stderr, never suppressed.

QUIET="${AFSYNC_QUIET:-0}"
say()   { [ "$QUIET" = "1" ] && return 0; printf '%s\n' "$*"; }
ok()    { say "  [ok]    $*"; }
skip()  { say "  [skip]  $*"; }
do_()   { say "  [do]    $*"; }
note()  { say "  [note]  $*"; }
warn()  { printf '  [warn]  %s\n' "$*" >&2; }
fail()  { printf '  [FAIL]  %s\n' "$*" >&2; exit 1; }

# =============================================================================
# 3. Path safety
# =============================================================================
# Every destructive operation goes through these. A variable that expands to
# empty, to $HOME, or to a shallow path aborts the run instead of deleting.

assert_safe_path() {
    local dir="${1:?assert_safe_path: empty path}"
    case "$dir" in
        /|"$HOME"|"$HOME"/) fail "refusing to operate on $dir" ;;
        *..*)               fail "refusing to operate on path containing '..': $dir" ;;
        /*)                 ;;
        *)                  fail "refusing to operate on relative path: $dir" ;;
    esac
    local depth
    depth="$(printf '%s' "${dir#/}" | awk -F/ '{print NF}')"
    [ "$depth" -ge 3 ] || fail "refusing to operate on shallow path: $dir"
}

safe_wipe() {
    # Delete the CONTENTS of a directory, leaving the directory itself.
    local dir="${1:?safe_wipe: empty path}"
    assert_safe_path "$dir"
    [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -delete
}

safe_rmtree() {
    local dir="${1:?safe_rmtree: empty path}"
    assert_safe_path "$dir"
    [ -e "$dir" ] || return 0
    rm -rf "$dir"
}

# =============================================================================
# 4. SHA-256 helpers
# =============================================================================

sha_file() {
    # SHA-256 of a single file's content; empty string if missing.
    [ -f "$1" ] && shasum -a 256 "$1" | awk '{print $1}' || echo ""
}

sha_dir() {
    # Aggregate SHA-256 of every file under a directory, in deterministic order.
    # Ignores editor temp files and our own backups.
    local dir="${1%/}"
    [ -d "$dir" ] || { echo ""; return; }
    ( cd "$dir" && find . -type f \
        ! -name '.*.bak-*' \
        ! -name '*.bak-*' \
        ! -name '.DS_Store' \
        ! -name '*.swp' \
        -print 2>/dev/null \
      | LC_ALL=C sort \
      | while read -r f; do
            sha_file "$f"
        done \
      | shasum -a 256 \
      | awk '{print $1}'
    )
}

# Aggregate SHA of all source-of-truth content the sync depends on.
# Used by sync_* steps so a single edit invalidates all platforms consistently.
#
# Computed once per run and memoized. Recomputing per step would hash the whole
# tree four times, and — worse — a file changing mid-run would hand different
# targets different checksums, leaving them permanently out of step with each
# other. One snapshot per run keeps every target consistent.
SOURCE_SHA_CACHE=""

source_sha() {
    if [ -z "$SOURCE_SHA_CACHE" ]; then
        local s
        s="$(sha_dir "$PROJECT_ROOT/skills")$(sha_dir "$PROJECT_ROOT/agents")$(sha_dir "$PROJECT_ROOT/rules")$(sha_dir "$PROJECT_ROOT/resources")$(sha_dir "$PROJECT_ROOT/scripts")$(sha_dir "$PROJECT_ROOT/global")$(sha_file "$PROJECT_ROOT/opencode.json")"
        SOURCE_SHA_CACHE="$(printf '%s' "$s" | shasum -a 256 | awk '{print $1}')"
    fi
    printf '%s' "$SOURCE_SHA_CACHE"
}

mode_sha() {
    # source_sha combined with MODE, for targets whose output depends on mode.
    printf '%s%s' "$(source_sha)" "$MODE" | shasum -a 256 | awk '{print $1}'
}

# =============================================================================
# 5. State (loaded once, flushed once, written atomically)
# =============================================================================
# STATE_FLAT holds "dotted.key=value" lines so lookups are pure bash.
# STATE_PENDING buffers writes; state_flush merges them in a single pass.

STATE_FLAT=""
STATE_PENDING=""

state_load() {
    STATE_FLAT=""
    [ -f "$STATE_FILE" ] || return 0
    STATE_FLAT="$(python3 - "$STATE_FILE" <<'PYEOF' || true
import json, sys

try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)

def walk(prefix, obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            walk(prefix + [key], value)
    else:
        print(".".join(prefix) + "=" + str(obj))

walk([], data)
PYEOF
)"
}

state_get() {
    # $1 = dotted key. Echoes the value, or "" when absent.
    [ -n "$STATE_FLAT" ] || return 0
    printf '%s\n' "$STATE_FLAT" \
      | awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'
}

state_set() {
    # $1 = dotted key, $2 = value. Buffered; written by state_flush.
    STATE_PENDING="${STATE_PENDING}${1}=${2}
"
}

state_flush() {
    [ -n "$STATE_PENDING" ] || return 0
    [ "$DRY_RUN" = "1" ] && return 0
    ensure_dir "$(dirname "$STATE_FILE")"
    # The pending buffer travels in the environment: stdin is already taken by
    # the heredoc that carries the program itself.
    AFSYNC_PENDING="$STATE_PENDING" python3 - "$STATE_FILE" <<'PYEOF'
import json, os, sys, tempfile

path = sys.argv[1]
try:
    with open(path) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}

for line in os.environ.get("AFSYNC_PENDING", "").splitlines():
    if not line:
        continue
    key, _, value = line.partition("=")
    parts = key.split(".")
    cur = data
    for part in parts[:-1]:
        nxt = cur.get(part)
        if not isinstance(nxt, dict):
            nxt = {}
            cur[part] = nxt
        cur = nxt
    cur[parts[-1]] = value

directory = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".state-")
try:
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
    raise
PYEOF
    STATE_PENDING=""
}

# =============================================================================
# 6. File helpers
# =============================================================================

ensure_dir() {
    mkdir -p "$@"
}

backup() {
    # Backup $1 to $1.bak-<ts> if it exists, then prune to the newest N.
    local f="${1:?backup: empty path}"
    [ -f "$f" ] || return 0
    cp "$f" "$f.bak-$(date -u +%Y%m%dT%H%M%SZ)"
    # Suffixes are ISO-8601 UTC, so a reverse lexical sort is newest-first —
    # no need to parse `ls -lt` output.
    local stale
    stale="$(find "$(dirname "$f")" -maxdepth 1 -name "$(basename "$f").bak-*" 2>/dev/null \
             | LC_ALL=C sort -r \
             | tail -n +$((BACKUP_KEEP + 1)))"
    if [ -n "$stale" ]; then
        printf '%s\n' "$stale" | while IFS= read -r old; do
            [ -n "$old" ] && rm -f "$old"
        done
    fi
    return 0
}

copy_skill_tree() {
    # Replace $2 with the full contents of skill dir $1.
    local src="${1:?}" dest="${2:?}"
    ensure_dir "$dest"
    safe_wipe "$dest"
    cp -R "$src"/. "$dest"/
}

copy_skills_into() {
    # Copy every skills/*/ that has a SKILL.md into skills root $1.
    local root="${1:?}" skill sname
    ensure_dir "$root"
    for skill in "$PROJECT_ROOT/skills/"*/; do
        [ -f "$skill/SKILL.md" ] || continue
        sname="$(basename "$skill")"
        copy_skill_tree "$skill" "$root/$sname"
    done
}

prune_stale_agent_skills() {
    # Remove skills that were once generated from agents/*.md.
    local root="${1:?}" stale
    for stale in $STALE_AGENT_SKILLS; do
        [ -d "$root/$stale" ] && safe_rmtree "$root/$stale"
    done
    return 0
}

copy_rules_and_resources() {
    # Mirror rules/ and resources/ under destination root $1.
    local root="${1:?}" f
    ensure_dir "$root/rules" "$root/resources"
    for f in "$PROJECT_ROOT/rules/"*.md; do
        cp "$f" "$root/rules/$(basename "$f")"
    done
    for f in "$PROJECT_ROOT/resources/"*; do
        cp -R "$f" "$root/resources/$(basename "$f")"
    done
}

strip_frontmatter() {
    # Output the body of a markdown file with YAML frontmatter removed.
    awk '
        NR == 1 && /^---$/ { in_fm = 1; next }
        in_fm && /^---$/   { in_fm = 0; next }
        !in_fm             { print }
    ' "$1"
}

# =============================================================================
# 7. Arg parsing
# =============================================================================

usage() {
    # Print the header comment block: skip the shebang and the shellcheck
    # directive, then every comment line until the first line of real code.
    # No hardcoded line numbers, so editing the header can never corrupt --help.
    awk '
        NR == 1         { next }
        /^# shellcheck/ { next }
        /^#/            { sub(/^# ?/, ""); print; next }
        { exit }
    ' "$0"
    exit "${1:-0}"
}

positional_seen=0
for arg in "$@"; do
    case "$arg" in
        --mode=*)             MODE="${arg#--mode=}" ;;
        --only=*)             ONLY="${arg#--only=}" ;;
        --skip-sync)          SKIP_SYNC=1 ;;
        --skip-permissions)   SKIP_PERMISSIONS=1 ;;
        --force)              FORCE=1 ;;
        --status)             DRY_RUN=1 ;;
        --reset)              RESET=1 ;;
        -h|--help)            usage 0 ;;
        -*)                   printf '  [FAIL]  Unknown option: %s\n' "$arg" >&2; usage 1 ;;
        *)
            # Legacy call form: `sync-skills.sh paths.txt`. Destinations are
            # fixed now, so consume it with a warning instead of hard-failing —
            # README, CLAUDE.md and plugins.txt still document this form.
            positional_seen=$((positional_seen + 1))
            [ "$positional_seen" -gt 1 ] && fail "unexpected extra argument: $arg"
            warn "ignoring legacy positional argument '$arg' — destinations are fixed; see --help"
            ;;
    esac
done

case "$MODE" in
    strict|smart|yolo) ;;
    *) fail "Bad --mode=$MODE (expected strict|smart|yolo)" ;;
esac

if [ -n "$ONLY" ]; then
    for t in $(printf '%s' "$ONLY" | tr ',' ' '); do
        case " $ALL_TOOLS " in
            *" $t "*) ;;
            *) fail "Bad --only=$t (expected one of: $ALL_TOOLS)" ;;
        esac
    done
fi

# =============================================================================
# 8. Target selection: installed AND requested?
# =============================================================================
# We don't auto-install anything. Each sync target only runs if its tool is
# present (CLI on PATH OR canonical config directory) and not filtered out by
# --only. Absent tools are reported and skipped — the user installs manually.

tool_installed() {
    case "$1" in
        claude)   [ -d "$CLAUDE_HOME" ]   || command -v claude   >/dev/null 2>&1 ;;
        opencode) [ -d "$OPENCODE_HOME" ] || command -v opencode >/dev/null 2>&1 ;;
        codex)    [ -d "$CODEX_HOME" ]    || command -v codex    >/dev/null 2>&1 ;;
        hermes)   [ -d "$HERMES_HOME" ]   || command -v hermes   >/dev/null 2>&1 ;;
        pi)       [ -d "$PI_AGENT_HOME" ] || command -v pi       >/dev/null 2>&1 ;;
        *)        return 1 ;;
    esac
}

tool_selected() {
    [ -z "$ONLY" ] && return 0
    case ",$ONLY," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

want_content() { [ "$SKIP_SYNC" != "1" ]; }
want_perms()   { [ "$SKIP_PERMISSIONS" != "1" ]; }

target_active() {
    # $1 = tool. Reports the reason and returns 1 when the target must be skipped.
    local t="$1"
    if ! tool_selected "$t"; then skip "$t (not in --only=$ONLY)"; return 1; fi
    if ! tool_installed "$t"; then skip "$t (not installed)";      return 1; fi
    if ! want_content && ! want_perms; then
        skip "$t (--skip-sync and --skip-permissions)"
        return 1
    fi
    return 0
}

tools_summary() {
    local marks="" t
    for t in $ALL_TOOLS; do
        if tool_installed "$t"; then marks="$marks$t ✓  "
        else                        marks="$marks$t ✗  "
        fi
    done
    say "Tools:  $marks"
    [ -n "$ONLY" ] && say "Only:   $ONLY"
    return 0
}

# =============================================================================
# 9. Step gating (one implementation, four callers)
# =============================================================================

step_begin() {
    # $1 = state key, $2 = current sha, $3 = label.
    # Returns 0 when the caller should run the step, non-zero to skip.
    local key="$1" cur="$2" label="$3"
    local cached last
    cached="$(state_get "$key.sha")"
    last="$(state_get "$key.at")"
    if [ "$FORCE" != "1" ] && [ -n "$cached" ] && [ "$cached" = "$cur" ]; then
        skip "$label (unchanged${last:+ since $last})"
        return 1
    fi
    do_ "$label  sha=${cur:0:12}  mode=$MODE"
    [ "$DRY_RUN" = "1" ] && return 1
    return 0
}

step_commit() {
    # $1 = state key, $2 = current sha, $3 = label.
    local key="$1" cur="$2" label="$3"
    state_set "$key.sha" "$cur"
    state_set "$key.at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ok "$label"
}

# =============================================================================
# 10. Managed settings: merge helpers
# =============================================================================
# Each helper preserves every key it does not own. A config that exists but
# cannot be parsed is left untouched and reported — we never clobber a file
# we failed to understand.

merge_json_keys() {
    # $1 = target .json, $2 = JSON object of managed keys.
    # Exit 3 from python means "unparseable target" — warn, don't write.
    local target="${1:?}" managed="${2:?}" rc=0
    python3 - "$target" "$managed" <<'PYEOF' || rc=$?
import json, os, sys, tempfile

path, managed = sys.argv[1], json.loads(sys.argv[2])

if os.path.exists(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception as exc:
        print("cannot parse %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(3)
    if not isinstance(data, dict):
        print("cannot merge %s: top level is not an object" % path, file=sys.stderr)
        sys.exit(3)
else:
    data = {}

# Managed keys win; every other key the user added is preserved.
data.update(managed)

directory = os.path.dirname(path) or "."
os.makedirs(directory, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".opencode-")
try:
    with os.fdopen(fd, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
    raise
PYEOF
    if [ "$rc" = "3" ]; then
        warn "left $target untouched (unparseable JSON) — fix it or delete it and re-run"
        return 1
    fi
    [ "$rc" = "0" ] || fail "failed to merge $target (exit $rc)"
    return 0
}

merge_toml_keys() {
    # $1 = target .toml, remaining args = `key=<toml-value>` fragments.
    # Surgical splice: only the named top-level keys are replaced or inserted,
    # above the first [table] header. Comments and layout survive verbatim
    # (tomli_w is not available, and re-serialising would drop comments).
    local target="${1:?}" rc=0
    shift
    python3 - "$target" "$@" <<'PYEOF' || rc=$?
import os, re, sys, tempfile

try:
    import tomllib
except ImportError:
    tomllib = None

path = sys.argv[1]
pairs = []
for item in sys.argv[2:]:
    key, _, value = item.partition("=")
    pairs.append((key, value))

src = ""
if os.path.exists(path):
    with open(path) as fh:
        src = fh.read()

if src.strip() and tomllib is not None:
    try:
        tomllib.loads(src)
    except Exception as exc:
        print("cannot parse %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(3)

marker = "# approval_policy and sandbox_mode are managed by scripts/sync-skills.sh"
lines = src.splitlines()
if marker not in src:
    lines.insert(0, marker)

# Managed keys live above the first table header; that is the insertion point.
boundary = len(lines)
for index, line in enumerate(lines):
    if re.match(r"^\s*\[", line):
        boundary = index
        break

for key, value in pairs:
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=")
    hit = None
    for index in range(boundary):
        if pattern.match(lines[index]):
            hit = index
            break
    replacement = "%s = %s" % (key, value)
    if hit is not None:
        lines[hit] = replacement
    else:
        lines.insert(boundary, replacement)
        boundary += 1

out = "\n".join(lines).rstrip("\n") + "\n"

if tomllib is not None:
    try:
        tomllib.loads(out)
    except Exception as exc:
        print("refusing to write invalid TOML to %s: %s" % (path, exc), file=sys.stderr)
        sys.exit(4)

directory = os.path.dirname(path) or "."
os.makedirs(directory, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".codex-")
try:
    with os.fdopen(fd, "w") as fh:
        fh.write(out)
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
    raise
PYEOF
    if [ "$rc" = "3" ]; then
        warn "left $target untouched (unparseable TOML) — fix it or delete it and re-run"
        return 1
    fi
    [ "$rc" = "0" ] || fail "failed to merge $target (exit $rc)"
    return 0
}

merge_yaml_block() {
    # $1 = target .yaml, $2 = top-level key, $3 = file holding the replacement
    # block (or "-" to delete the key). Textual splice so comments elsewhere in
    # the user's config survive; the result is validated with PyYAML when it is
    # available, so we never write a config the tool cannot read.
    local target="${1:?}" key="${2:?}" block="${3:?}" rc=0
    python3 - "$target" "$key" "$block" <<'PYEOF' || rc=$?
import os, re, sys, tempfile

path, key, block_path = sys.argv[1], sys.argv[2], sys.argv[3]

new_block = ""
if block_path != "-":
    with open(block_path) as fh:
        new_block = fh.read().rstrip("\n")

src = ""
if os.path.exists(path):
    with open(path) as fh:
        src = fh.read()

# The managed block is preceded by marker comments. They must be part of the
# match, otherwise each run re-inserts one and the file grows without bound.
# `*` (not `?`) also cleans up markers stacked by earlier buggy runs.
MARKER = "# managed by scripts/sync-skills.sh"
pattern = re.compile(
    r"(?:^" + re.escape(MARKER) + r"[^\n]*\n)*"
    r"^" + re.escape(key) + r":.*?(?=\n^\S|\Z)",
    re.M | re.S,
)

matches = list(pattern.finditer(src))
if matches:
    # Drop every existing copy of the block, then re-insert one where the
    # first copy used to be. Offsets below the first match stay valid because
    # every deletion happens at or after it.
    insert_at = matches[0].start()
    out = src
    for match in reversed(matches):
        out = out[:match.start()] + out[match.end():]
    if new_block:
        out = out[:insert_at] + new_block + out[insert_at:]
elif new_block:
    out = src.rstrip("\n") + ("\n\n" if src.strip() else "") + new_block + "\n"
else:
    out = src

# The block match ends at the newline before the next key, which swallows the
# blank separator line. Re-establish exactly one blank line before every
# managed block so repeated runs converge on a stable file.
out = re.sub(r"([^\n])\n(" + re.escape(MARKER) + ")", r"\1\n\n\2", out)
out = re.sub(r"\n{3,}", "\n\n", out).lstrip("\n")
if out and not out.endswith("\n"):
    out += "\n"

try:
    import yaml
    yaml.safe_load(out)
except ImportError:
    pass
except Exception as exc:
    print("refusing to write invalid YAML to %s: %s" % (path, exc), file=sys.stderr)
    sys.exit(4)

directory = os.path.dirname(path) or "."
os.makedirs(directory, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".hermes-")
try:
    with os.fdopen(fd, "w") as fh:
        fh.write(out)
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
    raise
PYEOF
    [ "$rc" = "0" ] || fail "failed to merge $key into $target (exit $rc)"
    return 0
}

# =============================================================================
# 11. Sync: Claude Code target
# =============================================================================
# Claude is "verbatim" — our agent/*.md files already use the CSV tool
# allow-list that Claude expects. Skills/rules/resources are copied as-is.

step_sync_claude() {
    target_active claude || return 0

    local key="sync.claude" label="sync:claude" cur
    cur="$(source_sha)"
    step_begin "$key" "$cur" "$label" || return 0

    ensure_dir "$CLAUDE_HOME/agents" "$CLAUDE_HOME/skills"

    if want_content; then
        local f
        for f in "$PROJECT_ROOT/agents/"*.md; do
            cp "$f" "$CLAUDE_HOME/agents/$(basename "$f")"
        done

        copy_skills_into "$CLAUDE_HOME/skills"
        prune_stale_agent_skills "$CLAUDE_HOME/skills"
        copy_rules_and_resources "$CLAUDE_HOME"

        if [ -f "$PROJECT_ROOT/global/CLAUDE.md" ]; then
            cp "$PROJECT_ROOT/global/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md"
        fi
    fi

    step_commit "$key" "$cur" "$label"
}

# =============================================================================
# 12. Sync: OpenCode target
# =============================================================================
# OpenCode rejects the Claude CSV `tools:` field, so it is translated into
# `permission:` denials. `mode:` IS read by OpenCode (primary vs subagent) and
# must survive; `model:` is dropped because Claude's bare `sonnet` is not a
# valid OpenCode `provider/model` id.

translate_claude_agent_to_opencode() {
    # $1 = source agent .md; stdout: opencode-formatted .md
    #
    # fm tracks frontmatter position: 0 before, 1 inside, 2 after. Only lines
    # while fm == 1 are eligible for stripping, so a markdown `---` rule or a
    # body line beginning `model:` passes through untouched.
    awk '
        BEGIN { fm = 0 }

        NR == 1 && $0 == "---" { fm = 1; print; next }

        fm == 1 && $0 == "---" {
            n = split(csv, parts, /[[:space:]]*,[[:space:]]*/)
            for (i = 1; i <= n; i++) {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                have[tolower(parts[i])] = 1
            }
            deny = ""
            if (!have["edit"] && !have["write"]) deny = deny "  edit: deny\n"
            if (!have["bash"])                   deny = deny "  bash: deny\n"
            if (!have["agent"] && !have["task"]) deny = deny "  task: deny\n"
            if (deny != "") printf "permission:\n%s", deny
            print "---"
            fm = 2
            next
        }

        fm == 1 {
            if ($0 ~ /^tools:[[:space:]]*/) {
                line = $0
                sub(/^tools:[[:space:]]*/, "", line)
                csv = line
                next
            }
            if ($0 ~ /^model:/) next
            print
            next
        }

        { print }
    ' "$1"
}

opencode_managed_json() {
    case "$MODE" in
        strict)
            cat <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "orchestrator",
  "permission": {
    "*": "ask",
    "read": "allow",
    "skill": "allow",
    "doom_loop": "ask"
  }
}
JSON
            ;;
        smart)
            cat <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "orchestrator",
  "permission": {
    "bash": {
      "*": "ask",
      "git *": "allow",
      "ls *": "allow",
      "cat *": "allow",
      "rtk *": "allow",
      "dagRobin *": "allow"
    },
    "edit": "allow",
    "read": "allow",
    "glob": "allow",
    "grep": "allow",
    "skill": "allow",
    "task": "allow",
    "webfetch": "ask",
    "websearch": "allow",
    "doom_loop": "ask",
    "external_directory": "ask"
  }
}
JSON
            ;;
        yolo)
            cat <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "orchestrator",
  "permission": "allow"
}
JSON
            ;;
    esac
}

step_sync_opencode() {
    target_active opencode || return 0

    local key="sync.opencode" label="sync:opencode" cur
    cur="$(mode_sha)"
    step_begin "$key" "$cur" "$label" || return 0

    ensure_dir "$OPENCODE_HOME/agents" "$OPENCODE_HOME/skills"

    if want_content; then
        local f
        for f in "$PROJECT_ROOT/agents/"*.md; do
            translate_claude_agent_to_opencode "$f" \
                > "$OPENCODE_HOME/agents/$(basename "$f")"
        done

        copy_skills_into "$OPENCODE_HOME/skills"
        prune_stale_agent_skills "$OPENCODE_HOME/skills"
        copy_rules_and_resources "$OPENCODE_HOME"
    fi

    if want_perms; then
        backup "$OPENCODE_CONFIG"
        merge_json_keys "$OPENCODE_CONFIG" "$(opencode_managed_json)" || true
    fi

    step_commit "$key" "$cur" "$label"
}

# =============================================================================
# 13. Sync: Codex CLI target
# =============================================================================
# Codex has no subagents; we copy skills and manage approval_policy +
# sandbox_mode inside the user's own config.toml.

step_sync_codex() {
    target_active codex || return 0

    local key="sync.codex" label="sync:codex" cur
    cur="$(mode_sha)"
    step_begin "$key" "$cur" "$label" || return 0

    if want_content; then
        copy_skills_into "$CODEX_HOME/skills"
    fi

    if want_perms; then
        local approval sandbox
        case "$MODE" in
            strict) approval='"on-request"'; sandbox='"workspace-write"'    ;;
            smart)  approval='"on-failure"'; sandbox='"workspace-write"'    ;;
            yolo)   approval='"never"';      sandbox='"danger-full-access"' ;;
        esac
        ensure_dir "$CODEX_HOME"
        backup "$CODEX_CONFIG"
        merge_toml_keys "$CODEX_CONFIG" \
            "approval_policy=$approval" \
            "sandbox_mode=$sandbox" || true
    fi

    step_commit "$key" "$cur" "$label"
}

# =============================================================================
# 14. Sync: Hermes Agent target
# =============================================================================
# The most involved step:
#   - Categorize source skills into category subdirs.
#   - Convert agents/*.md into slash-command skills under workflow/.
#   - Compose SOUL.md (preserving the Hermes default in SOUL.md.bak).
#   - Install skill-bundles from scripts/templates/.
#   - Merge approvals + command_allowlist into ~/.hermes/config.yaml.

hermes_category() {
    # $1 = skill or agent name → category dir, or "" when uncategorized.
    printf '%s\n' "$HERMES_CATEGORIES" \
      | awk -F: -v n="$1" '$1 == n { print $2; exit }'
}

hermes_agent_tags() {
    case "$1" in
        orchestrator)       echo 'orchestration, multi-agent, pipeline, dagrobin' ;;
        architect)          echo 'planning, architecture, design, exploration' ;;
        builder)            echo 'implementation, tdd, refactor, debug' ;;
        qa-evaluator)       echo 'qa, testing, verification, evaluation' ;;
        code-reviewer)      echo 'review, quality, spec-compliance, audit' ;;
        project-manager)    echo 'planning, tasks, sprints, dagrobin' ;;
        summarizer-auditor) echo 'audit, summary, status, snapshot' ;;
        *)                  echo "$1, multi-agent" ;;
    esac
}

# Converts agents/<name>.md → Hermes SKILL.md. Same frontmatter state machine
# as the OpenCode translator, so the two cannot drift.
agent_to_hermes_awk=$(cat <<'AWKEOF'
BEGIN { fm = 0 }

NR == 1 && $0 == "---" { fm = 1; print; next }

fm == 1 && $0 == "---" {
    print "version: 1.0.0"
    print "metadata:"
    print "  hermes:"
    print "    tags: [" tags "]"
    print "---"
    print ""
    print "# `/" name "` \xe2\x80\x94 Hermes slash command"
    print ""
    print "You are the Hermes `/" name "` slash command. When the"
    print "user invokes `/" name " <request>`, execute the workflow below."
    print ""
    print "**Hermes-native tools available:**"
    print ""
    print "- Terminal backends: `local`, `docker`, `ssh`, `singularity`, `modal`"
    print "- Parallel workstreams: `hermes moa` (Mixture of Agents)"
    print "- Persistent memory: `~/.hermes/memories/` (survives sessions)"
    print "- Skill chaining: `/cmd1 /cmd2 <request>` loads several skills per turn"
    print ""
    print "**Sibling skills you may chain with:** `/architect`," \
          " `/project-manager`, `/builder`, `/qa-evaluator`," \
          " `/code-reviewer`, `/summarizer-auditor`"
    print ""
    print "**Source-of-truth:** `../../agents/" name ".md`" \
          " (Claude Code format). This file is regenerated by" \
          " `scripts/sync-skills.sh`. **Edit the source.**"
    print ""
    print "---"
    print ""
    fm = 2
    next
}

fm == 1 {
    if ($0 ~ /^mode:/)  next
    if ($0 ~ /^tools:/) next
    if ($0 ~ /^model:/) next
    print
    next
}

{
    line = $0
    if (line ~ /Use the Agent tool/)        sub(/Use the Agent tool/, "Use slash-command stacking (`/<other-skill>`) or `hermes moa`", line)
    if (line ~ /git worktree add/)          sub(/git worktree add/,   "Hermes sandbox backend (local / Docker / SSH)", line)
    if (line ~ /git worktree /)             sub(/git worktree /,      "Hermes sandbox backend ", line)
    if (line ~ /git worktrees?/)            sub(/git worktrees?/,     "Hermes sandboxes", line)
    if (line ~ /[Bb]ackground agents?/)     sub(/[Bb]ackground agents?/, "`hermes moa` parallel workstreams", line)
    if (line ~ /Spawn isolated subagents?/) sub(/Spawn isolated subagents?/, "Use `hermes moa` for parallel isolated workstreams", line)
    if (line ~ /subagent/)                 gsub(/subagent/, "sub-skill (chain via `/<name>`)", line)
    if (line ~ /[Ss]ub-agent/)             gsub(/sub-agent/, "sub-skill", line)
    print line
}

END {
    print ""
    print "---"
    print ""
    print "## Hermes execution notes"
    print ""
    print "- This skill mirrors a Claude Code subagent; the orchestration"
    print "  logic is reused as-is. Tweak the source `agents/" name ".md`"
    print "  if something is missing, then re-run sync-skills.sh."
    print "- dagRobin task tracking: invoke via the `terminal` tool \xe2\x80\x94"
    print "  `dagRobin ready`, `dagRobin claim <id> -a builder-N`," \
          " `dagRobin update <id> --status done`."
    print "- RTK: prefix every shell command with `rtk` for token-optimized output."
    print "- When the original prompt says \"dispatch agent X\", chain the"
    print "  `/X` <args> slash command instead (skill stacking)."
}
AWKEOF
)

agent_to_hermes() {
    # $1 = source agent .md, $2 = dest SKILL.md, $3 = agent name, $4 = tags CSV
    awk -v name="$3" -v tags="$4" "$agent_to_hermes_awk" "$1" > "$2"
}

hermes_sync_skills() {
    local skills_dir="${1:?}" name_dir bn category dest skill sname uncategorized=""

    # Migrate orphan flat dirs at the top level into their category subdir.
    for name_dir in "$skills_dir"/*/; do
        [ -d "$name_dir" ] || continue
        bn="$(basename "$name_dir")"
        category="$(hermes_category "$bn")"
        [ -n "$category" ] || continue
        dest="$skills_dir/$category/$bn"
        if [ ! -d "$dest" ]; then
            ensure_dir "$skills_dir/$category"
            mv "$name_dir" "$dest"
        fi
    done

    # Copy source skills into the right category.
    for skill in "$PROJECT_ROOT/skills/"*/; do
        [ -f "$skill/SKILL.md" ] || continue
        sname="$(basename "$skill")"
        category="$(hermes_category "$sname")"
        if [ -n "$category" ]; then
            dest="$skills_dir/$category/$sname"
        else
            dest="$skills_dir/$sname"
            uncategorized="$uncategorized $sname"
        fi
        copy_skill_tree "$skill" "$dest"
    done

    if [ -n "$uncategorized" ]; then
        warn "hermes: uncategorized skills land at the top level:$uncategorized"
        warn "hermes: add them to HERMES_CATEGORIES in sync-skills.sh to group them"
    fi
}

hermes_sync_agents() {
    local skills_dir="${1:?}" f aname category cat_dir stale_root tags

    for f in "$PROJECT_ROOT/agents/"*.md; do
        [ -f "$f" ] || continue
        aname="$(basename "$f" .md)"
        category="$(hermes_category "$aname")"
        if [ -n "$category" ]; then cat_dir="$skills_dir/$category"
        else                        cat_dir="$skills_dir"
        fi

        # Wipe any prior copy of this agent across every category and the
        # top-level flat layout, then recreate it in the right place.
        for stale_root in "$skills_dir" "$skills_dir"/*; do
            [ -d "$stale_root/$aname" ] && safe_rmtree "$stale_root/$aname"
        done

        ensure_dir "$cat_dir/$aname"
        tags="$(hermes_agent_tags "$aname")"
        agent_to_hermes "$f" "$cat_dir/$aname/SKILL.md" "$aname" "$tags"
    done
}

hermes_compose_soul() {
    # Preserve the Hermes default identity in SOUL.md.bak, then append our
    # engineering workflow guidance below it.
    local soul="$HERMES_HOME/SOUL.md"
    local bak="$HERMES_HOME/SOUL.md.bak"
    if [ ! -f "$bak" ] && [ -f "$soul" ]; then
        cp "$soul" "$bak"
    fi
    {
        printf '%s\n' ""
        printf '%s\n' "<!-- ====================================================== -->"
        printf '%s\n' "<!-- AUTO-MANAGED BY skills/scripts/sync-skills.sh            -->"
        printf '%s\n' "<!-- Edit project/global/CLAUDE.md + rules/{engineering,rtk}.md -->"
        printf '%s\n' "<!-- instead of editing the block below directly.              -->"
        printf '%s\n' "<!-- ====================================================== -->"
        printf '%s\n' ""
        cat "$bak" 2>/dev/null || cat "$PROJECT_ROOT/global/CLAUDE.md" 2>/dev/null || true
        printf '%s\n' ""
        printf '%s\n' "## Engineering workflow (afa/skills adapter)"
        printf '%s\n' ""
        printf '%s\n' "- Use dagRobin CLI for sprint/task tracking (\`dagRobin ready\`, \`dagRobin claim\`, \`dagRobin update\`)."
        printf '%s\n' "- Run \`rtk <cmd>\` prefix on shell commands for token-optimized output."
        printf '%s\n' "- Prefer simple systems over clever systems. Verify with tests before marking tasks done."
        printf '%s\n' "- Frontend/UI work: load the \`/better-interface\` skill first for design coordination."
        printf '%s\n' "- Bug reports: use the \`/systematic-debugging\` skill pattern before touching code."
        printf '%s\n' "- Multi-file features: orchestrator route (see \`/orchestrator\` skill) \xe2\x80\x94 estimate complexity first."
    } > "$soul"
}

hermes_write_settings() {
    local approvals allowlist
    approvals="$(mktemp)"
    allowlist="$(mktemp)"

    case "$MODE" in
        strict)
            cat > "$approvals" <<'YAML'
# managed by scripts/sync-skills.sh
approvals:
  mode: manual
  cron_mode: deny
  mcp_reload_confirm: true
  destructive_slash_confirm: true
YAML
            cat > "$allowlist" <<'YAML'
# managed by scripts/sync-skills.sh
command_allowlist: []
YAML
            ;;
        smart)
            cat > "$approvals" <<'YAML'
# managed by scripts/sync-skills.sh
approvals:
  mode: smart
  timeout: 300
  cron_mode: deny
  mcp_reload_confirm: true
  destructive_slash_confirm: true
YAML
            cat > "$allowlist" <<'YAML'
# managed by scripts/sync-skills.sh
command_allowlist:
  - "git status*"
  - "git diff*"
  - "rtk *"
  - "dagRobin *"
  - "hermes skills list*"
  - "hermes bundles list*"
YAML
            ;;
        yolo)
            cat > "$approvals" <<'YAML'
# managed by scripts/sync-skills.sh
approvals:
  mode: off
  cron_mode: deny
  mcp_reload_confirm: false
  destructive_slash_confirm: false
YAML
            # yolo defines no allowlist — any prior block is removed, since it
            # is meaningless at approvals.mode: off.
            : > "$allowlist"
            ;;
    esac

    backup "$HERMES_CONFIG"
    merge_yaml_block "$HERMES_CONFIG" "approvals" "$approvals"
    if [ -s "$allowlist" ]; then
        merge_yaml_block "$HERMES_CONFIG" "command_allowlist" "$allowlist"
    else
        merge_yaml_block "$HERMES_CONFIG" "command_allowlist" "-"
    fi

    rm -f "$approvals" "$allowlist"
}

step_sync_hermes() {
    target_active hermes || return 0

    local key="sync.hermes" label="sync:hermes" cur
    cur="$(mode_sha)"
    step_begin "$key" "$cur" "$label" || return 0

    local skills_dir="$HERMES_HOME/skills"
    local bundles_dir="$HERMES_HOME/skill-bundles"
    ensure_dir "$skills_dir" "$bundles_dir"

    if want_content; then
        hermes_sync_skills "$skills_dir"
        hermes_sync_agents "$skills_dir"

        # Install skill-bundles from scripts/templates/.
        local tmpl
        for tmpl in "$SCRIPT_DIR/templates/"*.yaml "$SCRIPT_DIR/templates/"*.yml; do
            [ -f "$tmpl" ] || continue
            cp "$tmpl" "$bundles_dir/$(basename "$tmpl")"
        done

        hermes_compose_soul
    fi

    if want_perms; then
        hermes_write_settings
    fi

    step_commit "$key" "$cur" "$label"
}

# =============================================================================
# 15. Sync: Pi coding agent target (pi.dev)
# =============================================================================
# Pi keeps everything under ~/.pi/agent/:
#   skills/   — SKILL.md packages, byte-identical to the Claude format
#   agents/   — subagent definitions (name/description/tools/model frontmatter)
#   AGENTS.md — the global context file, loaded before any project file
#
# Pi's settings.json has NO permission, sandbox or tool-allowlist surface, so
# --mode has nothing to map onto here. This target is content-only: it keys off
# source_sha (not mode_sha) and does nothing under --skip-sync. We deliberately
# do not touch settings.json — it holds the user's provider/model choices.

# Claude tool names → Pi's built-ins (read, bash, edit, write, grep, find, ls).
# Anything without a Pi equivalent (Agent/Task, WebFetch, WebSearch, …) is
# dropped rather than guessed at.
translate_claude_agent_to_pi() {
    awk '
        BEGIN { fm = 0 }

        NR == 1 && $0 == "---" { fm = 1; print; next }

        fm == 1 && $0 == "---" {
            if (csv != "") {
                n = split(csv, parts, /[[:space:]]*,[[:space:]]*/)
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                    t = tolower(parts[i])
                    if      (t == "read")  have["read"]  = 1
                    else if (t == "edit")  have["edit"]  = 1
                    else if (t == "write") have["write"] = 1
                    else if (t == "grep")  have["grep"]  = 1
                    else if (t == "bash")  have["bash"]  = 1
                    else if (t == "glob") { have["find"] = 1; have["ls"] = 1 }
                }
                m = split("read bash edit write grep find ls", ord, " ")
                mapped = ""
                for (i = 1; i <= m; i++)
                    if (have[ord[i]])
                        mapped = mapped (mapped == "" ? "" : ", ") ord[i]
                if (mapped != "") print "tools: " mapped
            }
            print "---"
            fm = 2
            next
        }

        fm == 1 {
            if ($0 ~ /^tools:[[:space:]]*/) {
                line = $0
                sub(/^tools:[[:space:]]*/, "", line)
                csv = line
                next
            }
            # Pi infers the model from the session; `mode:` is not part of its
            # schema. Both are Claude/OpenCode-specific.
            if ($0 ~ /^model:/) next
            if ($0 ~ /^mode:/)  next
            print
            next
        }

        { print }
    ' "$1"
}

compose_global_agents_md() {
    # Build a global context file from global/CLAUDE.md plus the always-on rules.
    local out="${1:?}"
    {
        printf '# Global agent instructions\n\n'
        printf 'Auto-generated by scripts/sync-skills.sh — edit the sources, not this file.\n\n'
        cat "$PROJECT_ROOT/global/CLAUDE.md" 2>/dev/null || true
        printf '\n## Engineering rules\n\n'
        strip_frontmatter "$PROJECT_ROOT/rules/engineering.md"
        printf '\n## RTK command prefix\n\n'
        strip_frontmatter "$PROJECT_ROOT/rules/rtk.md"
        printf '\n## dagRobin task tracking\n\n'
        strip_frontmatter "$PROJECT_ROOT/rules/dagrobin.md"
    } > "$out"
}

step_sync_pi() {
    target_active pi || return 0

    local key="sync.pi" label="sync:pi" cur
    cur="$(source_sha)"
    step_begin "$key" "$cur" "$label" || return 0

    if want_content; then
        ensure_dir "$PI_AGENT_HOME/agents" "$PI_AGENT_HOME/skills"

        local f
        for f in "$PROJECT_ROOT/agents/"*.md; do
            translate_claude_agent_to_pi "$f" \
                > "$PI_AGENT_HOME/agents/$(basename "$f")"
        done

        copy_skills_into "$PI_AGENT_HOME/skills"
        prune_stale_agent_skills "$PI_AGENT_HOME/skills"

        backup "$PI_AGENT_HOME/AGENTS.md"
        compose_global_agents_md "$PI_AGENT_HOME/AGENTS.md"
    fi

    step_commit "$key" "$cur" "$label"
}

# =============================================================================
# 16. Step: per-project AGENTS.md (opt-in)
# =============================================================================
# Driven by HERMES_ADAPTER_WRITE_AGENTS=1 + HERMES_ADAPTER_PROJECT_DIR=<path>.
# Writes <project>/AGENTS.md with engineering + rtk + dagrobin rules, plus
# any stack-specific rule we auto-detect.

detect_project_stacks() {
    # Emits space-separated stack names whose rules we should append.
    local proj="$1"
    local hits=""
    if [ -f "$proj/package.json" ] || [ -f "$proj/tsconfig.json" ]; then hits="$hits typescript"; fi
    if [ -f "$proj/svelte.config.js" ] || [ -f "$proj/svelte.config.ts" ]; then hits="$hits svelte"; fi
    if [ -f "$proj/src-tauri/tauri.conf.json" ] || [ -f "$proj/tauri.conf.json" ]; then hits="$hits tauri"; fi
    if [ -f "$proj/Cargo.toml" ]; then hits="$hits rust"; fi
    if [ -f "$proj/pyproject.toml" ] || [ -f "$proj/requirements.txt" ] || [ -f "$proj/setup.py" ]; then hits="$hits python"; fi
    if [ -f "$proj/go.mod" ]; then hits="$hits golang"; fi
    if find "$proj" -maxdepth 4 \
        \( -name '*_test.go' -o -name 'test_*.py' -o -name '*_test.py' \
           -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' \
           -o -name '*.spec.ts' -o -type d -name 'tests' -o -type d -name '__tests__' \) \
        -print -quit 2>/dev/null | grep -q .; then
        hits="$hits testing"
    fi
    printf '%s\n' "$hits"
}

step_project_agents_md() {
    if [ -z "${HERMES_ADAPTER_WRITE_AGENTS:-}" ] || [ -z "${HERMES_ADAPTER_PROJECT_DIR:-}" ]; then
        return 0
    fi

    local proj="$HERMES_ADAPTER_PROJECT_DIR"
    local out="$proj/AGENTS.md"
    [ -d "$proj" ] || fail "HERMES_ADAPTER_PROJECT_DIR is not a directory: $proj"

    if [ -f "$out" ] && [ -z "${HERMES_ADAPTER_FORCE:-}" ]; then
        skip "agents-md:$out (already exists; set HERMES_ADAPTER_FORCE=1 to overwrite)"
        return 0
    fi

    do_ "agents-md:$proj"
    [ "$DRY_RUN" = "1" ] && return 0

    local stacks rule s
    stacks="$(detect_project_stacks "$proj")"
    {
        printf '# Project instructions for Hermes Agent\n\n'
        printf 'Auto-generated by scripts/sync-skills.sh on %s.\n\n' "$(date -u +%Y-%m-%d)"
        printf '## Engineering rules\n\n'
        strip_frontmatter "$PROJECT_ROOT/rules/engineering.md"
        printf '\n## RTK command prefix\n\n'
        strip_frontmatter "$PROJECT_ROOT/rules/rtk.md"
        printf '\n## dagRobin task tracking\n\n'
        strip_frontmatter "$PROJECT_ROOT/rules/dagrobin.md"
        for s in $stacks; do
            rule="$PROJECT_ROOT/rules/$s.md"
            [ -f "$rule" ] || continue
            printf '\n## %s\n\n' "$(printf '%s' "$s" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
            strip_frontmatter "$rule"
        done
    } > "$out"
    ok "agents-md:$out"
}

# =============================================================================
# 17. Main
# =============================================================================

main() {
    say "=== sync-skills (mode=$MODE) ==="
    [ "$DRY_RUN" = "1" ] && say "  DRY RUN — no writes"
    [ "$FORCE"   = "1" ] && say "  FORCE — ignoring cached checksums"

    if [ "$RESET" = "1" ]; then
        case "$STATE_FILE" in
            */state.json)
                if [ "$DRY_RUN" = "1" ]; then
                    note "would clear state: $STATE_FILE"
                else
                    rm -f "$STATE_FILE"
                    note "state cleared: $STATE_FILE"
                fi
                ;;
            *) fail "refusing to --reset an unexpected state path: $STATE_FILE" ;;
        esac
    fi

    tools_summary
    state_load

    step_sync_claude
    step_sync_opencode
    step_sync_codex
    step_sync_hermes
    step_sync_pi
    step_project_agents_md

    state_flush

    say ""
    if [ "$DRY_RUN" = "1" ]; then
        say "Status complete (dry run) — nothing was written."
    else
        say "Done. Re-run anytime; only changed steps will execute."
    fi
}

# Flush whatever completed even if a later step aborts, so a partial run does
# not force a full re-sync next time.
trap 'state_flush' EXIT

main "$@"
