#!/usr/bin/env bash
# shellcheck shell=bash
#
# test-sync-skills.sh — sandboxed test suite for scripts/sync-skills.sh.
#
# Every case runs the real script against a throwaway $HOME under mktemp -d,
# with HERMES_HOME and AFSYNC_STATE redirected there, so the suite can never
# touch ~/.claude, ~/.config/opencode, ~/.codex or ~/.hermes.
#
# The source-of-truth repo is a hermetic fixture tree, not this repository, so
# assertions can be exact and the suite stays fast.
#
# Usage: bash scripts/test-sync-skills.sh [-v]
#   -v   echo the script's own output for each case (debugging)
#
# Exits non-zero if any case fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sync-skills.sh"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

start() { printf '\n=== %s\n' "$1"; }

pass() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }

fault() {
    FAIL=$((FAIL + 1))
    printf '  FAIL  %s\n' "$1"
    [ -n "${2:-}" ] && printf '        %s\n' "$2"
    return 0
}

check() {
    # check <description> <condition-exit-code-already-evaluated>
    if [ "$2" = "0" ]; then pass "$1"; else fault "$1"; fi
}

assert_file() {
    if [ -f "$1" ]; then pass "${2:-exists: $1}"
    else fault "${2:-exists: $1}" "missing file: $1"; fi
}

assert_dir() {
    if [ -d "$1" ]; then pass "${2:-exists: $1}"
    else fault "${2:-exists: $1}" "missing dir: $1"; fi
}

assert_contains() {
    # assert_contains <file> <fixed-string> <description>
    if [ -f "$1" ] && grep -qF -- "$2" "$1"; then pass "$3"
    else fault "$3" "expected '$2' in $1"; fi
}

assert_not_contains() {
    if [ -f "$1" ] && grep -qF -- "$2" "$1"; then
        fault "$3" "unexpected '$2' in $1"
    else pass "$3"; fi
}

assert_eq() {
    # assert_eq <actual> <expected> <description>
    if [ "$1" = "$2" ]; then pass "$3"
    else fault "$3" "expected '$2', got '$1'"; fi
}

assert_count() {
    # assert_count <file> <pattern> <n> <description>
    local n
    n="$(grep -cE -- "$2" "$1" 2>/dev/null || true)"
    n="$(printf '%s' "$n" | tr -d '[:space:]')"
    assert_eq "${n:-0}" "$3" "$4"
}

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

REPO="$ROOT/repo"

build_fixture_repo() {
    mkdir -p "$REPO"/{agents,skills,rules,resources,global,scripts/templates}
    cp "$SUT" "$REPO/scripts/sync-skills.sh"
    chmod +x "$REPO/scripts/sync-skills.sh"

    # An agent whose BODY contains a markdown rule and a line starting
    # "model:". Both must survive translation — this is the regression fixture
    # for the frontmatter state machine.
    cat > "$REPO/agents/fixture-agent.md" <<'EOF'
---
name: fixture-agent
description: Fixture used by the test suite.
mode: subagent
tools: Read, Grep
model: sonnet
---

Body starts here.

---

model: this-line-is-body-text-and-must-survive
tools: also body text
EOF

    cat > "$REPO/agents/builder.md" <<'EOF'
---
name: builder
description: Fixture builder agent.
mode: subagent
tools: Read, Edit, Write, Bash
model: sonnet
---

Builder body.
EOF

    # One categorized skill, one uncategorized (must trigger a warning).
    mkdir -p "$REPO/skills/better-ui" "$REPO/skills/demo-skill"
    printf -- '---\nname: better-ui\n---\n\nDesign skill fixture.\n' \
        > "$REPO/skills/better-ui/SKILL.md"
    printf -- '---\nname: demo-skill\n---\n\nUncategorized fixture.\n' \
        > "$REPO/skills/demo-skill/SKILL.md"
    printf 'nested asset\n' > "$REPO/skills/better-ui/asset.txt"

    for r in engineering rtk dagrobin; do
        printf '# %s\n\nRule fixture.\n' "$r" > "$REPO/rules/$r.md"
    done

    # ADHD-friendly voice rule (also embedded in global/CLAUDE.md) so we can
    # assert it lands in OpenCode, Claude, Hermes and Pi on every sync run.
    printf '# Voice — ADHD-Friendly\n\nUser has ADHD. Reply in cave-man.\n' \
        > "$REPO/rules/voice-adhd.md"

    printf 'resource fixture\n' > "$REPO/resources/note.md"
    printf '# Global\n\nGlobal fixture.\n\n## Voice — ADHD-Friendly\n\nUser has ADHD. Reply in cave-man.\n' > "$REPO/global/CLAUDE.md"
    cat > "$REPO/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json"
}
EOF
    printf 'name: feature\nskills: [builder]\n' \
        > "$REPO/scripts/templates/feature-bundle.yaml"
}

new_home() {
    # Fresh fake HOME with all four tool markers, so every target activates.
    local home="$ROOT/home-$1"
    rm -rf "$home"
    mkdir -p "$home"/.claude "$home"/.config/opencode "$home"/.codex "$home"/.hermes "$home"/.pi/agent
    printf '%s' "$home"
}

run_sync() {
    # run_sync <fake-home> [args...] ; stdout+stderr captured to $OUT, rc in $RC
    local home="$1"; shift
    OUT="$(HOME="$home" \
           HERMES_HOME="$home/.hermes" \
           PI_HOME="$home/.pi" \
           AFSYNC_STATE="$home/.afasync/state.json" \
           bash "$REPO/scripts/sync-skills.sh" "$@" 2>&1)"
    RC=$?
    [ "$VERBOSE" = "1" ] && printf '%s\n' "$OUT" | sed 's/^/      | /'
    return 0
}

tree_sum() {
    # Deterministic checksum of a tree, ignoring our own timestamped backups.
    ( cd "$1" 2>/dev/null || return 0
      find . -type f ! -name '*.bak-*' -print 2>/dev/null \
        | LC_ALL=C sort \
        | while read -r f; do
              printf '%s ' "$f"
              shasum -a 256 "$f" | awk '{print $1}'
          done
    ) | shasum -a 256 | awk '{print $1}'
}

build_fixture_repo

# ---------------------------------------------------------------------------
# Case 1 — fresh install lands every tree
# ---------------------------------------------------------------------------

start "1. fresh install"
H="$(new_home fresh)"
run_sync "$H"
assert_eq "$RC" "0" "exits 0"

assert_file "$H/.claude/agents/builder.md"          "claude: agents copied"
assert_dir  "$H/.claude/skills/better-ui"           "claude: skills copied"
assert_file "$H/.claude/skills/better-ui/asset.txt" "claude: nested skill files copied"
assert_file "$H/.claude/rules/engineering.md"       "claude: rules copied"
assert_file "$H/.claude/resources/note.md"          "claude: resources copied"
assert_file "$H/.claude/CLAUDE.md"                  "claude: global CLAUDE.md copied"

assert_file "$H/.config/opencode/agents/builder.md"  "opencode: agents copied"
assert_file "$H/.config/opencode/rules/engineering.md" "opencode: rules copied"
assert_file "$H/.config/opencode/opencode.json"      "opencode: config written"

assert_dir  "$H/.codex/skills/better-ui"             "codex: skills copied"
assert_file "$H/.codex/config.toml"                  "codex: config written"

assert_dir  "$H/.hermes/skills/design/better-ui"          "hermes: categorized skill"
assert_dir  "$H/.hermes/skills/demo-skill"                "hermes: uncategorized skill at top level"
assert_file "$H/.hermes/skills/workflow/builder/SKILL.md" "hermes: agent → slash command"
assert_file "$H/.hermes/SOUL.md"                          "hermes: SOUL.md composed"
assert_file "$H/.hermes/skill-bundles/feature-bundle.yaml" "hermes: bundle installed"
assert_file "$H/.hermes/config.yaml"                      "hermes: config written"

assert_file "$H/.pi/agent/agents/builder.md"     "pi: agents copied"
assert_dir  "$H/.pi/agent/skills/better-ui"      "pi: skills copied"
assert_file "$H/.pi/agent/AGENTS.md"             "pi: global AGENTS.md composed"

# Voice — ADHD-Friendly must reach every target that picks up rules.
# These guard against future regressions in the sync script (e.g. if Hermes
# again falls back to SOUL.md.bak instead of global/CLAUDE.md).
assert_contains "$H/.claude/CLAUDE.md" \
    "Voice — ADHD-Friendly" \
    "claude: voice block present in global CLAUDE.md"
assert_contains "$H/.config/opencode/rules/voice-adhd.md" \
    "Voice — ADHD-Friendly" \
    "opencode: voice rule copied to rules/"
assert_contains "$H/.hermes/SOUL.md" \
    "Voice — ADHD-Friendly" \
    "hermes: voice block injected into SOUL.md (not just .bak fallback)"
assert_contains "$H/.pi/agent/AGENTS.md" \
    "Voice — ADHD-Friendly" \
    "pi: voice block present in composed AGENTS.md"

case "$OUT" in
    *"uncategorized skills"*) pass "warns about uncategorized skills" ;;
    *) fault "warns about uncategorized skills" "no warning in output" ;;
esac

# ---------------------------------------------------------------------------
# Case 2 — idempotency: second run skips everything and writes nothing
# ---------------------------------------------------------------------------

start "2. idempotency"
BEFORE="$(tree_sum "$H")"
run_sync "$H"
AFTER="$(tree_sum "$H")"
assert_eq "$RC" "0" "second run exits 0"
assert_eq "$AFTER" "$BEFORE" "second run changes nothing on disk"
assert_count <(printf '%s\n' "$OUT") '\[skip\]' 5 "all five targets report [skip]"

# ---------------------------------------------------------------------------
# Case 3 — --status is read-only
# ---------------------------------------------------------------------------

start "3. --status writes nothing"
H="$(new_home status)"
BEFORE="$(tree_sum "$H")"
run_sync "$H" --status
AFTER="$(tree_sum "$H")"
assert_eq "$RC" "0" "exits 0"
assert_eq "$AFTER" "$BEFORE" "fake HOME untouched"
if [ -f "$H/.afasync/state.json" ]; then
    fault "no state written" "state.json exists after --status"
else
    pass "no state written"
fi
case "$OUT" in
    *"DRY RUN"*) pass "announces dry run" ;;
    *) fault "announces dry run" ;;
esac

# ---------------------------------------------------------------------------
# Case 4 — --force re-runs on a cache hit
# ---------------------------------------------------------------------------

start "4. --force ignores the cache"
H="$(new_home force)"
run_sync "$H"
run_sync "$H" --force
assert_eq "$RC" "0" "exits 0"
assert_count <(printf '%s\n' "$OUT") '\[do\]' 5 "all five targets re-run"
assert_count <(printf '%s\n' "$OUT") '\[skip\]' 0 "nothing is skipped"

# ---------------------------------------------------------------------------
# Case 5 — managed settings merge, foreign keys preserved
# ---------------------------------------------------------------------------

start "5. config merge preserves foreign keys"
H="$(new_home merge)"

cat > "$H/.codex/config.toml" <<'EOF'
# user's own comment
model = "o3"
approval_policy = "never"

[mcp_servers.foo]
command = "foo-server"
EOF

cat > "$H/.config/opencode/opencode.json" <<'EOF'
{
  "theme": "my-custom-theme",
  "default_agent": "somebody-else"
}
EOF

cat > "$H/.hermes/config.yaml" <<'EOF'
custom_block:
  keep_me: true

approvals:
  mode: manual
EOF

run_sync "$H" --mode=smart
assert_eq "$RC" "0" "exits 0"

# Codex: managed keys updated, everything else byte-preserved.
assert_contains "$H/.codex/config.toml" 'approval_policy = "on-failure"' "codex: managed key updated"
assert_contains "$H/.codex/config.toml" 'sandbox_mode = "workspace-write"' "codex: managed key inserted"
assert_contains "$H/.codex/config.toml" 'model = "o3"'            "codex: foreign key preserved"
assert_contains "$H/.codex/config.toml" '[mcp_servers.foo]'       "codex: foreign table preserved"
assert_contains "$H/.codex/config.toml" 'command = "foo-server"'  "codex: foreign table body preserved"
assert_contains "$H/.codex/config.toml" "# user's own comment"    "codex: comment preserved"
assert_count "$H/.codex/config.toml" '^approval_policy' 1         "codex: no duplicated managed key"
python3 -c "import tomllib,sys; tomllib.load(open('$H/.codex/config.toml','rb'))" 2>/dev/null
check "codex: result is valid TOML" "$?"

# OpenCode: managed keys win, foreign key survives.
assert_contains "$H/.config/opencode/opencode.json" 'my-custom-theme' "opencode: foreign key preserved"
assert_contains "$H/.config/opencode/opencode.json" '"default_agent": "orchestrator"' "opencode: managed key wins"
python3 -c "import json;json.load(open('$H/.config/opencode/opencode.json'))" 2>/dev/null
check "opencode: result is valid JSON" "$?"

# Hermes: managed blocks replaced in place, foreign block survives.
assert_contains "$H/.hermes/config.yaml" 'custom_block:'   "hermes: foreign block preserved"
assert_contains "$H/.hermes/config.yaml" 'keep_me: true'   "hermes: foreign block body preserved"
assert_contains "$H/.hermes/config.yaml" 'mode: smart'     "hermes: approvals updated"
assert_count "$H/.hermes/config.yaml" '^approvals:' 1      "hermes: approvals not duplicated"
assert_count "$H/.hermes/config.yaml" '^command_allowlist:' 1 "hermes: allowlist not duplicated"
python3 -c "import yaml;yaml.safe_load(open('$H/.hermes/config.yaml'))" 2>/dev/null
check "hermes: result is valid YAML" "$?"

# Repeated runs must not grow the YAML. This is the historical corruption
# mode: the marker comment sat outside the replaced region, so every run
# prepended another one until the file was hundreds of lines and unparseable.
LINES_1="$(wc -l < "$H/.hermes/config.yaml" | tr -d ' ')"
run_sync "$H" --mode=smart --force
run_sync "$H" --mode=smart --force
LINES_3="$(wc -l < "$H/.hermes/config.yaml" | tr -d ' ')"
assert_eq "$LINES_3" "$LINES_1" "hermes: config.yaml does not grow across runs"

# ...and an already-corrupted config must heal, not stay broken.
start "5b. hermes self-heals a corrupted config"
H="$(new_home heal)"
{
    printf 'custom_block:\n  keep_me: true\n\n'
    for _ in 1 2 3 4 5; do printf '# managed by scripts/sync-skills.sh\n'; done
    printf 'approvals:\n  mode: manual\n'
} > "$H/.hermes/config.yaml"
run_sync "$H" --mode=smart
assert_count "$H/.hermes/config.yaml" '^# managed by' 2 "stacked markers collapse to one per block"
assert_contains "$H/.hermes/config.yaml" 'keep_me: true' "foreign block still preserved"
HEAL_1="$(wc -l < "$H/.hermes/config.yaml" | tr -d ' ')"
run_sync "$H" --mode=smart --force
HEAL_2="$(wc -l < "$H/.hermes/config.yaml" | tr -d ' ')"
assert_eq "$HEAL_2" "$HEAL_1" "healed config is stable on the next run"
python3 -c "import yaml;yaml.safe_load(open('$H/.hermes/config.yaml'))" 2>/dev/null
check "healed config is valid YAML" "$?"

# An unparseable config must be left alone, not clobbered.
start "5c. unparseable config is never clobbered"
printf '{ this is not json' > "$H/.config/opencode/opencode.json"
run_sync "$H" --force
assert_contains "$H/.config/opencode/opencode.json" 'this is not json' "opencode: unparseable config left untouched"
case "$OUT" in
    *"unparseable JSON"*) pass "opencode: warns about unparseable config" ;;
    *) fault "opencode: warns about unparseable config" ;;
esac

# ---------------------------------------------------------------------------
# Case 6 — frontmatter translation
# ---------------------------------------------------------------------------

start "6. frontmatter translation"
H="$(new_home fm)"
run_sync "$H"
OC="$H/.config/opencode/agents/fixture-agent.md"

assert_contains     "$OC" 'mode: subagent'   "opencode: mode: preserved"
assert_not_contains "$OC" 'model: sonnet'    "opencode: model: stripped from frontmatter"
assert_not_contains "$OC" 'tools: Read, Grep' "opencode: tools: CSV stripped"
assert_contains     "$OC" 'permission:'      "opencode: permission block emitted"
assert_contains     "$OC" 'edit: deny'       "opencode: edit denied (no Edit/Write in tools)"
assert_contains     "$OC" 'bash: deny'       "opencode: bash denied (no Bash in tools)"
assert_count        "$OC" '^permission:' 1   "opencode: exactly one permission block"

# The regression: body content must survive a markdown rule and body-level
# lines that happen to start with a frontmatter key name.
assert_contains "$OC" 'model: this-line-is-body-text-and-must-survive' \
    "opencode: body line starting 'model:' survives"
assert_contains "$OC" 'tools: also body text' \
    "opencode: body line starting 'tools:' survives"

# The builder fixture has Edit/Write/Bash, so only task should be denied.
OCB="$H/.config/opencode/agents/builder.md"
assert_not_contains "$OCB" 'edit: deny' "opencode: edit allowed when tools list Edit/Write"
assert_not_contains "$OCB" 'bash: deny' "opencode: bash allowed when tools list Bash"
assert_contains     "$OCB" 'task: deny' "opencode: task denied (no Agent/Task in tools)"

# Pi: tools map to its lowercase built-ins; mode:/model: are not in its schema.
PI="$H/.pi/agent/agents/builder.md"
assert_contains     "$PI" 'tools: read, bash, edit, write' "pi: tools mapped to built-ins"
assert_not_contains "$PI" 'mode:'        "pi: mode: dropped"
assert_not_contains "$PI" 'model: sonnet' "pi: model: dropped"
assert_contains     "$PI" 'name: builder' "pi: name preserved"
assert_contains     "$PI" 'Builder body.' "pi: body preserved"

# Read+Grep only: no bash/edit/write, and Glob absent so no find/ls.
PIF="$H/.pi/agent/agents/fixture-agent.md"
assert_contains     "$PIF" 'tools: read, grep' "pi: read-only agent maps to read, grep"
assert_not_contains "$PIF" 'bash'              "pi: bash not granted when absent"
assert_contains     "$PIF" 'model: this-line-is-body-text-and-must-survive' \
    "pi: body line starting 'model:' survives"

# Pi has no permission surface, so --mode must not touch it.
PI_SHA_A="$(shasum -a 256 "$PI" | awk '{print $1}')"
run_sync "$H" --mode=yolo --force
PI_SHA_B="$(shasum -a 256 "$PI" | awk '{print $1}')"
assert_eq "$PI_SHA_B" "$PI_SHA_A" "pi: output identical across --mode changes"
if [ -f "$H/.pi/agent/settings.json" ]; then
    fault "pi: settings.json left alone" "script created settings.json"
else
    pass "pi: settings.json left alone (holds user provider/model choices)"
fi

# Hermes conversion drops mode/tools/model but keeps the body.
HS="$H/.hermes/skills/workflow/builder/SKILL.md"
assert_contains     "$HS" 'version: 1.0.0'    "hermes: version injected"
assert_contains     "$HS" 'tags: ['           "hermes: tags injected"
assert_not_contains "$HS" 'model: sonnet'     "hermes: model: stripped"
assert_contains     "$HS" 'Builder body.'     "hermes: body preserved"

# ---------------------------------------------------------------------------
# Case 7 — mode matrix
# ---------------------------------------------------------------------------

start "7. mode matrix"
for m in strict smart yolo; do
    H="$(new_home "mode-$m")"
    run_sync "$H" "--mode=$m"
    assert_eq "$RC" "0" "$m: exits 0"
    case "$m" in
        strict)
            assert_contains "$H/.codex/config.toml"       'approval_policy = "on-request"' "$m: codex approval_policy"
            assert_contains "$H/.hermes/config.yaml"      'mode: manual'                   "$m: hermes approvals.mode"
            assert_contains "$H/.config/opencode/opencode.json" '"*": "ask"'               "$m: opencode permission"
            ;;
        smart)
            assert_contains "$H/.codex/config.toml"       'approval_policy = "on-failure"' "$m: codex approval_policy"
            assert_contains "$H/.hermes/config.yaml"      'mode: smart'                    "$m: hermes approvals.mode"
            assert_contains "$H/.hermes/config.yaml"      'command_allowlist:'             "$m: hermes allowlist present"
            ;;
        yolo)
            assert_contains     "$H/.codex/config.toml"  'approval_policy = "never"'          "$m: codex approval_policy"
            assert_contains     "$H/.codex/config.toml"  'sandbox_mode = "danger-full-access"' "$m: codex sandbox_mode"
            assert_not_contains "$H/.hermes/config.yaml" 'command_allowlist:'                 "$m: hermes allowlist removed"
            assert_contains     "$H/.config/opencode/opencode.json" '"permission": "allow"'   "$m: opencode permission"
            ;;
    esac
done

# Switching modes must replace, never append.
start "7b. mode switch does not duplicate keys"
H="$(new_home mode-switch)"
run_sync "$H" --mode=strict
run_sync "$H" --mode=smart
run_sync "$H" --mode=yolo
run_sync "$H" --mode=smart
assert_count "$H/.hermes/config.yaml" '^approvals:'         1 "hermes: one approvals block after 4 mode switches"
assert_count "$H/.hermes/config.yaml" '^command_allowlist:' 1 "hermes: one allowlist block after 4 mode switches"
assert_count "$H/.codex/config.toml"  '^approval_policy'    1 "codex: one approval_policy after 4 mode switches"
assert_count "$H/.codex/config.toml"  '^sandbox_mode'       1 "codex: one sandbox_mode after 4 mode switches"

# ---------------------------------------------------------------------------
# Case 8 — --reset
# ---------------------------------------------------------------------------

start "8. --reset"
H="$(new_home reset)"
run_sync "$H"
assert_file "$H/.afasync/state.json" "state written by first run"
run_sync "$H" --reset
assert_eq "$RC" "0" "exits 0"
case "$OUT" in
    *"state cleared"*) pass "reports state cleared" ;;
    *) fault "reports state cleared" ;;
esac
assert_count <(printf '%s\n' "$OUT") '\[do\]' 5 "all targets rebuild after reset"

# ---------------------------------------------------------------------------
# Case 9 — CLI contract
# ---------------------------------------------------------------------------

start "9. CLI contract"
H="$(new_home cli)"

run_sync "$H" paths.txt --status
assert_eq "$RC" "0" "legacy positional arg still exits 0"
case "$OUT" in
    *"ignoring legacy positional argument"*) pass "legacy positional arg warns" ;;
    *) fault "legacy positional arg warns" ;;
esac

run_sync "$H" --nonsense
assert_eq "$RC" "1" "unknown option exits 1"
case "$OUT" in
    *"Unknown option"*) pass "unknown option is reported" ;;
    *) fault "unknown option is reported" ;;
esac

run_sync "$H" --mode=bogus
assert_eq "$RC" "1" "bad --mode exits 1"

run_sync "$H" --only=nope
assert_eq "$RC" "1" "bad --only exits 1"

run_sync "$H" --only=claude --force
assert_eq "$RC" "0" "--only=claude exits 0"
case "$OUT" in
    *"opencode (not in --only"*) pass "--only filters other targets" ;;
    *) fault "--only filters other targets" ;;
esac

run_sync "$H" --help
assert_eq "$RC" "0" "--help exits 0"
case "$OUT" in
    *"sync-skills.sh — Single source of truth"*) pass "--help prints the title line" ;;
    *) fault "--help prints the title line" "header block not fully rendered" ;;
esac
case "$OUT" in
    *"AFSYNC_QUIET"*) pass "--help prints the Environment section" ;;
    *) fault "--help prints the Environment section" "header block truncated" ;;
esac

# Fatal errors must survive AFSYNC_QUIET.
QOUT="$(HOME="$H" HERMES_HOME="$H/.hermes" PI_HOME="$H/.pi" AFSYNC_STATE="$H/.afasync/state.json" \
        AFSYNC_QUIET=1 bash "$REPO/scripts/sync-skills.sh" --mode=bogus 2>&1)"
case "$QOUT" in
    *"Bad --mode"*) pass "fatal errors visible under AFSYNC_QUIET=1" ;;
    *) fault "fatal errors visible under AFSYNC_QUIET=1" "got: $QOUT" ;;
esac

# ---------------------------------------------------------------------------
# Case 10 — backup pruning
# ---------------------------------------------------------------------------

start "10. backup pruning"
H="$(new_home backups)"
run_sync "$H"
for _ in 1 2 3 4 5 6 7 8; do
    HOME="$H" HERMES_HOME="$H/.hermes" PI_HOME="$H/.pi" AFSYNC_STATE="$H/.afasync/state.json" \
        AFSYNC_BACKUP_KEEP=3 bash "$REPO/scripts/sync-skills.sh" --force >/dev/null 2>&1
done
N="$(find "$H/.hermes" -maxdepth 1 -name 'config.yaml.bak-*' | wc -l | tr -d ' ')"
if [ "$N" -le 3 ]; then pass "backups pruned to AFSYNC_BACKUP_KEEP (found $N)"
else fault "backups pruned to AFSYNC_BACKUP_KEEP" "found $N backups, expected <= 3"; fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n---------------------------------------------\n'
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'RESULT: FAIL\n'
    exit 1
fi
printf 'RESULT: PASS\n'
