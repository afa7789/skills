#!/usr/bin/env bash
# solidity-audit.sh — Reproducible 4-phase Solidity security audit pipeline
#
# Usage:
#   ./solidity-audit.sh <command> [options]
#
# Commands:
#   init <repo-path>          Phase 1: malware check + repo setup
#   scan <repo-path>          Phase 3: 6 parallel finding-discovery passes
#   classify <repo-path>      Phase 3.8: dedupe + rank + patch-history
#   reproduce <repo-path>     Phase 4.2: write ExploitV1 tests, run them
#   fix <repo-path>           Phase 4.4: build v2 with true-positive fixes
#   verify <repo-path>        Phase 4.8: 3-run forge test verification
#   all <repo-path>           Run all phases end-to-end
#   help                      Show this help
#
# Options (per command):
#   --src <path>              Contracts dir (default: auto-detected from foundry.toml,
#                             else src/ or contracts/)
#   --test <path>             Tests dir (default: auto-detected, else test/ or tests/)
#   --findings <path>         Path to findings dir (default: <repo>/findings)
#   --worktree <path>         Use an existing worktree (skip git mv)
#   --skip-malware            Skip Phase 1 (pure source repo)
#   --classes <list>          Comma-separated check IDs (default: every check
#                             found in the checklist, e.g. S01..S35)
#   --checklist <path>        Checklist that DEFINES the checks
#                             (default: ../skills/solidity-review/reference/checklist.md)
#   --contract <name>         Contract under test (default: auto)
#   --retries <n>             Exploit-test rewrite attempts (default: 2)
#   --skip-claude             Skip the Claude second-opinion pass
#   --model <name>            Model for opencode (default: opencode/big-pickle)
#   --agent <name>            Agent for opencode (default: orchestrator)
#   --extra-requirement <txt> Extra requirement appended to the v2 fix prompt
#   --bounty-bands <txt>      Program reward bands for ranking (opt-in)
#   --report <path>           Output report path (default: /tmp/v2-build-report.md)
#   --dry-run                 Print commands without running them
#   --verbose                 Print every command before running
#
# Example:
#   ./solidity-audit.sh all ~/work/myproject --report ~/audit.md

set -euo pipefail

VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The audit taxonomy is the solidity-review skill's checklist — one section per
# check (S01, S02, ...). Discovery reads the actual section text out of it, so
# the classes are defined in exactly one place instead of being bare labels.
CHECKLIST="$SCRIPT_DIR/../skills/solidity-review/reference/checklist.md"

# Defaults
REPO=""
SRC=""
TEST_DIR=""
FINDINGS_DIR=""
WORKTREE=""
SKIP_MALWARE=0
CLASSES=""                 # empty => every check found in $CHECKLIST
CONTRACT=""                # empty => auto-detect the largest .sol in $SRC
MAX_TEST_RETRIES=2
SKIP_CLAUDE=0
MODEL="opencode/big-pickle"
AGENT="orchestrator"
EXTRA_REQUIREMENT=""
BOUNTY_BANDS=""        # opt-in; reward bands are program-specific
REPORT="/tmp/v2-build-report.md"
DRY_RUN=0
VERBOSE=0
COMMAND=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }

run() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "[DRY-RUN] $*"
  else
    if [ "$VERBOSE" = 1 ]; then
      echo "[RUN] $*"
    fi
    "$@"
  fi
}

require() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing: $1 (install: $2)"; exit 1; }
}

# ---------- arg parsing ----------
while [ $# -gt 0 ]; do
  case "$1" in
    init|scan|classify|reproduce|fix|verify|all|help|--help|-h)
      COMMAND="$1"; shift ;;
    --src)        SRC="$2"; shift 2 ;;
    --test)       TEST_DIR="$2"; shift 2 ;;
    --findings)   FINDINGS_DIR="$2"; shift 2 ;;
    --worktree)   WORKTREE="$2"; shift 2 ;;
    --skip-malware) SKIP_MALWARE=1; shift ;;
    --classes)    CLASSES="$2"; shift 2 ;;
    --checklist)  CHECKLIST="$2"; shift 2 ;;
    --contract)   CONTRACT="$2"; shift 2 ;;
    --retries)    MAX_TEST_RETRIES="$2"; shift 2 ;;
    --skip-claude) SKIP_CLAUDE=1; shift ;;
    --model)      MODEL="$2"; shift 2 ;;
    --agent)      AGENT="$2"; shift 2 ;;
    --extra-requirement) EXTRA_REQUIREMENT="$2"; shift 2 ;;
    --bounty-bands) BOUNTY_BANDS="$2"; shift 2 ;;
    --report)     REPORT="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -*)           err "Unknown flag: $1"; exit 1 ;;
    *)
      if [ -z "$REPO" ]; then REPO="$1"; shift
      else err "Unexpected positional arg: $1"; exit 1
      fi ;;
  esac
done

show_help() {
  # Print the header comment block: everything from line 2 until the first
  # line that is not a comment. No hardcoded line range to drift.
  awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit 0
}

[ "$COMMAND" = "help" ] || [ "$COMMAND" = "--help" ] || [ "$COMMAND" = "-h" ] && show_help

[ -z "$COMMAND" ] && { err "No command. Run: $0 help"; exit 1; }
[ -z "$REPO" ] && { err "No <repo-path> provided."; exit 1; }

REPO="$(cd "$REPO" 2>/dev/null && pwd || echo "$REPO")"
[ -d "$REPO" ] || { err "Repo not found: $REPO"; exit 1; }

# Locate the Foundry project root: the nearest dir containing foundry.toml.
# Falls back to common layouts so this works on any repo, not one specific tree.
detect_foundry_root() {
  local hit
  hit="$(find "$REPO" -maxdepth 3 -name foundry.toml -not -path '*/lib/*' -not -path '*/node_modules/*' 2>/dev/null | sort | head -1)"
  [ -n "$hit" ] && { dirname "$hit"; return 0; }
  local d
  for d in "$REPO" "$REPO"/*/; do
    [ -d "$d/src" ] || [ -d "$d/contracts" ] || continue
    printf '%s' "${d%/}"
    return 0
  done
  printf '%s' "$REPO"
}

# Pick the contract under test: --contract wins, else the largest .sol under
# $SRC that is not an interface, library, mock or the preserved V1 copy.
detect_contract() {
  if [ -n "$CONTRACT" ]; then printf '%s' "$CONTRACT"; return 0; fi
  find "$SRC" -name '*.sol' -not -path '*/lib/*' -not -path '*/interfaces/*' \
       -not -name 'I[A-Z]*.sol' -not -name '*V1.sol' -not -name 'Mock*.sol' 2>/dev/null \
    | while IFS= read -r f; do printf '%s %s\n' "$(wc -c < "$f" | tr -d ' ')" "$f"; done \
    | sort -rn | head -1 | awk '{print $2}' | xargs -I{} basename {} .sol
}

# Set defaults relative to the detected project root
FOUNDRY_ROOT="$(detect_foundry_root)"
if [ -z "$SRC" ]; then
  for cand in "$FOUNDRY_ROOT/src" "$FOUNDRY_ROOT/contracts" "$REPO/src" "$REPO/contracts"; do
    [ -d "$cand" ] && { SRC="$cand"; break; }
  done
  [ -z "$SRC" ] && SRC="$FOUNDRY_ROOT/src"
fi
if [ -z "$TEST_DIR" ]; then
  for cand in "$FOUNDRY_ROOT/test" "$FOUNDRY_ROOT/tests" "$REPO/test" "$REPO/tests"; do
    [ -d "$cand" ] && { TEST_DIR="$cand"; break; }
  done
  [ -z "$TEST_DIR" ] && TEST_DIR="$FOUNDRY_ROOT/test"
fi
[ -z "$FINDINGS_DIR" ] && FINDINGS_DIR="$REPO/findings"
[ -z "$WORKTREE" ]     && WORKTREE="$REPO"

# Phase commands --------------------------------------------------------

phase1_malware() {
  log "Phase 1: malware / host-isolation check on $REPO"
  if [ "$SKIP_MALWARE" = 1 ]; then
    ok "Skipped (--skip-malware)"
    return 0
  fi

  # Inspect installers, hooks, archives
  local findings=()

  # package.json pre/post-install hooks
  if [ -f "$REPO/package.json" ]; then
    if grep -E '"(preinstall|postinstall|install)"' "$REPO/package.json" | grep -v 'npm run' | head -3; then
      findings+=("package.json has install hooks — review manually")
    fi
  fi

  # Suspicious shell patterns
  local susp=$(grep -rEn 'curl[^|]+\|.*sh|wget[^|]+\|.*bash|eval\s*\([^)]*\$' "$REPO" \
    --include='*.sh' --include='*.js' --include='*.ts' --include='*.py' --include='*.sol' \
    --include='*.toml' --include='*.json' 2>/dev/null | grep -vE '(test|spec|fixture)' | head -5)
  if [ -n "$susp" ]; then
    findings+=("Suspicious pipe-to-shell or eval patterns found")
    echo "$susp"
  fi

  # Symlink bombs in zips
  while IFS= read -r zip; do
    if unzip -l "$zip" 2>/dev/null | grep -E '(\.\./|->\s*/)'; then
      findings+=("Path traversal or symlink in $zip")
    fi
  done < <(find "$REPO" -maxdepth 3 -name '*.zip' 2>/dev/null)

  if [ ${#findings[@]} -gt 0 ]; then
    err "MALWARE CHECK FAILED. ${#findings[@]} indicator(s):"
    printf '  - %s\n' "${findings[@]}"
    return 1
  fi
  ok "No malware indicators found"
}

phase2_read_code() {
  log "Phase 2: read code (orientation)"
  require find "brew install findutils"
  require wc "system"

  local src_files=$(find "$SRC" -name '*.sol' 2>/dev/null | wc -l)
  local test_files=$(find "$TEST_DIR" -name '*.sol' 2>/dev/null | wc -l)
  log "  contracts: $src_files .sol files in $SRC"
  log "  tests:     $test_files .sol files in $TEST_DIR"
  log "  Skim contract names:"
  for f in $(find "$SRC" -name '*.sol' -maxdepth 1 2>/dev/null); do
    local name=$(basename "$f" .sol)
    log "    - $name"
  done
}

# Emit the check IDs present in the checklist, e.g. S01 S02 ... S35.
checklist_ids() {
  grep -oE '^#{2,3} [A-Z][0-9]{2}' "$CHECKLIST" 2>/dev/null \
    | awk '{print $2}' | sort -u
}

# Emit one check's full section text (header through the next header).
checklist_section() {
  awk -v id="$1" '
    $0 ~ "^#{2,3} " id " " { inside = 1; print; next }
    inside && /^#{2,3} [A-Z][0-9]{2} / { exit }
    inside { print }
  ' "$CHECKLIST"
}

phase3_discovery() {
  log "Phase 3: multi-tool finding discovery"
  require opencode "https://opencode.ai"

  [ -f "$CHECKLIST" ] || {
    err "Checklist not found: $CHECKLIST"
    err "Pass --checklist <path> (default: the solidity-review skill's reference/checklist.md)"
    exit 1
  }

  mkdir -p "$FINDINGS_DIR"

  # Resolve which checks to run: --classes, else every check in the checklist.
  local -a cls=()
  if [ -n "$CLASSES" ]; then
    local IFS=','
    cls=($CLASSES)
    unset IFS
  else
    while IFS= read -r id; do
      [ -n "$id" ] && cls+=("$id")
    done < <(checklist_ids)
  fi
  [ ${#cls[@]} -gt 0 ] || { err "No checks resolved from $CHECKLIST"; exit 1; }

  # 3.1 — One opencode subagent per check, each carrying that check's own text
  # from the solidity-review checklist. This is what makes the class defined.
  log "3.1 — dispatching ${#cls[@]} opencode subagents (source: $(basename "$CHECKLIST"))"
  local -a pids=()
  for class in "${cls[@]}"; do
    local section
    section="$(checklist_section "$class")"
    if [ -z "$section" ]; then
      warn "3.1 — $class not found in checklist, skipping"
      continue
    fi
    local prompt="You are a Solidity security auditor. Audit the contracts under $SRC for exactly ONE vulnerability class, defined below.

--- BEGIN CHECK DEFINITION ($class) ---
$section
--- END CHECK DEFINITION ---

Read every .sol file under $SRC fully before answering. Report ONLY instances of this specific check.
Output markdown, one '## $class-<n> — <title>' section per instance, each with: severity, file:line, the offending snippet, and the fix.
If there are no instances, output exactly '## $class — N/A'.
Do NOT modify any code."
    local outfile="$FINDINGS_DIR/opencode-${class}.md"
    run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$prompt" > "$outfile" 2>&1 &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid" || warn "subagent $pid failed"; done
  ok "opencode subagents done ($(find "$FINDINGS_DIR" -maxdepth 1 -name 'opencode-*.md' | wc -l | tr -d ' ') files)"

  # 3.2 — Holistic pass with the solidity-review skill itself (whole checklist
  # at once, rather than one check at a time — catches cross-check interactions).
  log "3.2 — solidity-review holistic pass"
  local review_prompt="Load the solidity-review skill and apply its full checklist to every .sol file under $SRC.
Output a severity-graded markdown report, one '## SR-<n> — <title>' section per finding, each with severity, file:line, snippet and fix. Do NOT modify code."
  run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$review_prompt" \
    > "$FINDINGS_DIR/solidity-review.md" 2>&1 || warn "3.2 — solidity-review pass failed"

  # 3.3 — Second opinion from a different vendor's agent.
  if [ "$SKIP_CLAUDE" = 1 ]; then
    warn "3.3 — claude second opinion skipped (--skip-claude)"
  elif command -v claude >/dev/null; then
    log "3.3 — claude second opinion"
    local claude_prompt="Act as an independent Solidity security reviewer giving a second opinion. Audit every .sol file under $SRC. Output markdown, one '## CL-<n> — <title>' section per finding, each with severity, file:line, snippet and fix. Do NOT modify code."
    run claude -p "$claude_prompt" > "$FINDINGS_DIR/claude.md" 2>&1 \
      || warn "3.3 — claude pass failed"
  else
    warn "3.3 — claude not installed, skipping second opinion"
  fi

  # 3.3 — Aderyn (if installed)
  if command -v aderyn >/dev/null; then
    log "3.3 — running aderyn"
    run aderyn --root "$REPO" --output "$FINDINGS_DIR/aderyn.md" || warn "aderyn failed"
  else
    warn "3.3 — aderyn not installed, skipping"
  fi

  # 3.6 — Slither
  if command -v slither >/dev/null; then
    log "3.6 — running slither"
    run slither . --filter-paths "node_modules|lib|test" > "$FINDINGS_DIR/slither.md" 2>&1 \
      || warn "slither exit non-zero (often has findings, that's fine)"
  else
    warn "3.6 — slither not installed. Install: pipx install slither-analyzer"
  fi
}

phase3_8_classify() {
  log "Phase 3.8: dedupe + rank + patch-history (3 subagents)"
  require opencode "https://opencode.ai"
  require jq "brew install jq"

  # 3.7 — Consolidate raw findings.
  # Previously this ran a python3 heredoc quoted with <<'PYEOF', so
  # "$FINDINGS_DIR" reached python as a literal string and the glob always
  # matched nothing. Now it is plain shell + jq, with jq doing the JSON quoting.
  log "3.7 — consolidating raw findings into raw.json"
  {
    local found=0
    while IFS= read -r path; do
      [ -s "$path" ] || continue
      local stem
      stem="$(basename "$path" .md)"
      # Every '## <ID> — <title>' heading becomes one raw finding.
      while IFS= read -r heading; do
        local fid title
        fid="$(printf '%s' "$heading" | sed -E 's/^#{2,3} +([^ ]+) +[—-].*/\1/')"
        title="$(printf '%s' "$heading" | sed -E 's/^#{2,3} +[^ ]+ +[—-] *//')"
        [ -n "$fid" ] || continue
        [ "$title" = "N/A" ] && continue
        jq -nc --arg s "$stem" --arg i "$fid" --arg t "$title" \
          '{source_file:$s, finding_id:$i, title:$t, file:null, line:null, summary:null}'
        found=$((found + 1))
      done < <(grep -hE '^#{2,3} +[^ ]+ +[—-] +' "$path" 2>/dev/null)
    done < <(find "$FINDINGS_DIR" -maxdepth 1 -name '*.md' | sort)
  } | jq -s '.' > "$FINDINGS_DIR/raw.json"
  ok "3.7 — wrote $(jq 'length' "$FINDINGS_DIR/raw.json") findings to raw.json"

  # Dispatch 3 subagents in parallel
  log "Dispatching dedupe + ranker + patch-check (3 subagents in background)"

  local pids=()
  local dedup_prompt="You are a Solidity auditor doing semantic deduplication. INPUT: $FINDINGS_DIR/raw.json. TASK: Cluster findings by same root cause + same code location + same exploit path. Output JSON only with shape: {\"clusters\":[{\"canonical_id\":\"...\",\"member_ids\":[...],\"title\":\"...\",\"root_cause\":\"...\",\"severity\":\"...\",\"file\":\"...\",\"line\":N}],\"stats\":{...}}. Every input finding id appears exactly once. Choose canonical_id preferring opencode over slither."
  local bounty_note=""
  [ -n "$BOUNTY_BANDS" ] && bounty_note="Reward bands for this program: $BOUNTY_BANDS Include minimum_reward and maximum_reward per finding."
  local ranker_prompt="You are a Solidity triager ranking canonical findings. INPUT: $FINDINGS_DIR/deduped.json. OUTPUT JSON only: {\"rankings\":[{\"canonical_id\":\"...\",\"rank\":1,\"impact_level\":\"Critical|High|Medium|Low|Info\",\"reasoning\":\"...\",\"root_bug\":\"...\"}],\"summary\":\"...\",\"missing_from_prompt\":\"...\"}. Rank by exploitability and blast radius. $bounty_note"
  local patch_prompt="You are a Solidity auditor doing snapshot verification (not patch-history). INPUT: $FINDINGS_DIR/ranked.json. For each finding, read the cited file:line in the current code and confirm whether the vulnerable pattern is still present. OUTPUT JSON: {\"still_present_status\":[{\"canonical_id\":\"...\",\"still_present\":true|false|needs_manual_review,\"evidence\":\"...\",\"reason\":\"...\"}],\"stats\":{...},\"note\":\"...\"}."

  (
    opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$dedup_prompt" \
      > "$FINDINGS_DIR/deduped.raw.txt" 2>&1
  ) & pids+=($!)

  (
    opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$ranker_prompt" \
      > "$FINDINGS_DIR/ranked.raw.txt" 2>&1
  ) & pids+=($!)

  (
    opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$patch_prompt" \
      > "$FINDINGS_DIR/patch-status.raw.txt" 2>&1
  ) & pids+=($!)

  for pid in "${pids[@]}"; do wait "$pid" || warn "classify subagent $pid failed"; done
  ok "classify done. Extract JSONs from .raw.txt files (see extract script)"

  # Extract the JSON payload out of each agent transcript. Agents wrap their
  # answer in prose and ANSI colour, so strip escapes and let jq find the
  # largest parseable object rather than hand-rolling a brace matcher.
  extract_json "deduped.raw.txt"     "deduped.json"
  extract_json "ranked.raw.txt"      "ranked.json"
  extract_json "patch-status.raw.txt" "patch-status.json"
}

extract_json() {
  local raw="$FINDINGS_DIR/$1" out="$FINDINGS_DIR/$2"
  if [ ! -f "$raw" ]; then
    warn "extract: $1 missing"
    return 0
  fi
  # Strip ANSI, then try each candidate object start until one parses whole.
  local text
  text="$(sed -E 's/\x1b\[[0-9;]*m//g' "$raw")"
  local start
  for start in $(printf '%s' "$text" | grep -bo '{' | cut -d: -f1 | tac); do
    if printf '%s' "${text:$start}" | jq -e '.' >/dev/null 2>&1; then
      printf '%s' "${text:$start}" | jq '.' > "$out"
      ok "extract: $2"
      return 0
    fi
  done
  warn "extract: $1 → no parseable JSON found"
  return 0
}

phase4_reproduce() {
  log "Phase 4.2: write ExploitV1 tests, run them until they reproduce"
  require forge "https://book.getfoundry.sh"
  require opencode "https://opencode.ai"

  local workdir
  workdir="$(dirname "$TEST_DIR")"

  local contract_note=""
  [ -n "$CONTRACT" ] && contract_note="The contract under test is $CONTRACT. "

  log "Dispatching subagent to write ExploitV1.t.sol"
  local prompt="You are a Solidity QA engineer. Read $FINDINGS_DIR/deduped.json (and $FINDINGS_DIR/ranked.json if present). ${contract_note}Write $TEST_DIR/ExploitV1.t.sol with one test per confirmed finding. Each test name starts with test_Exploit_<canonical_id>. Each test is written to FAIL against the vulnerable code — it asserts a property the vulnerability violates. Each test body starts with a comment block naming canonical_id, severity, file:line and root_cause. Follow the setup pattern of the existing tests in $TEST_DIR. Do NOT modify the contracts under $SRC."
  run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$prompt" \
    || warn "ExploitV1 subagent failed"

  # Step 10 of the audit spec: a test that does not reproduce the defect is
  # not evidence. Re-dispatch with the failure output until it does, bounded.
  local attempt=0 out
  while :; do
    log "Running ExploitV1 (attempt $((attempt + 1))/$((MAX_TEST_RETRIES + 1)))"
    out="$(cd "$workdir" && forge test --match-path 'test/ExploitV1*' 2>&1 || true)"

    if printf '%s' "$out" | grep -qE '\[FAIL|FAIL:|Failing tests:'; then
      ok "ExploitV1 reproduces the defect (tests fail against v1, as intended)"
      break
    fi

    if printf '%s' "$out" | grep -qiE 'compiler error|Compilation failed|Error \(' ; then
      warn "ExploitV1 does not compile"
    else
      warn "ExploitV1 compiled but nothing failed — the tests do not reproduce anything"
    fi

    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$MAX_TEST_RETRIES" ]; then
      err "ExploitV1 still does not reproduce after $attempt rewrite attempt(s)."
      err "Do not treat these findings as confirmed. Inspect $TEST_DIR/ExploitV1.t.sol by hand."
      break
    fi

    log "Rewriting ExploitV1.t.sol (attempt $attempt)"
    local retry_prompt="The exploit tests you wrote at $TEST_DIR/ExploitV1.t.sol do not reproduce the defects. A valid test MUST FAIL against the vulnerable contract, for the reason the finding claims. Here is the forge output:

$out

Rewrite $TEST_DIR/ExploitV1.t.sol so each test actually exercises its vulnerability and fails for the claimed reason. Fix any compilation errors. Do NOT modify the contracts under $SRC, and do NOT weaken assertions just to force a failure."
    run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$retry_prompt" \
      || warn "ExploitV1 rewrite subagent failed"
  done

  mkdir -p "$FINDINGS_DIR"
  printf '%s\n' "$out" > "$FINDINGS_DIR/baseline-v1.txt"
  printf '%s\n' "$out" | tail -5
}

phase4_fix() {
  log "Phase 4.4: build v2 with true-positive fixes"
  require opencode "https://opencode.ai"
  require forge "https://book.getfoundry.sh"

  local target
  target="$(detect_contract)"
  [ -n "$target" ] || { err "No contract found under $SRC. Pass --contract <Name>."; return 1; }

  local extra_arg=""
  [ -n "$EXTRA_REQUIREMENT" ] && extra_arg="Additional requirement for v2: $EXTRA_REQUIREMENT"

  log "Dispatching v2 builder subagent (contract: $target)"
  local prompt="You are a senior Solidity engineer building a remediated v2.

INPUTS — the confirmed findings, produced by this pipeline:
  $FINDINGS_DIR/ranked.json        (severity-ranked canonical findings)
  $FINDINGS_DIR/patch-status.json  (which are still present in current code)

TASK:
1. Preserve the vulnerable original so the exploit tests keep compiling: copy
   $SRC/${target}.sol to $SRC/${target}V1.sol and rename the contract to
   ${target}V1. Do not modify its logic — it is the baseline the ExploitV1
   tests assert against.
2. Apply fixes to $SRC/${target}.sol for the confirmed true-positive findings
   ONLY. Every change must trace to a finding id from ranked.json. Do not
   refactor, rename or restructure anything no finding motivated.
3. Choose remediations idiomatic to the libraries this project ALREADY uses —
   inspect its imports and remappings first. Do not introduce a new dependency
   unless a finding cannot be fixed without one; if you do, say which and why.
4. If the contract is upgradeable, preserve storage layout; state explicitly
   whether your changes are layout-compatible.
5. Update any test, script or deploy file that referenced the original so it
   points at the V1 path where it should test the old behaviour.
6. Build: cd $FOUNDRY_ROOT && forge build — confirm zero errors.
7. Re-run the exploit suite: cd $FOUNDRY_ROOT && forge test --match-path 'test/ExploitV1*' and confirm the V1 tests still fail as expected.
$extra_arg

REPORT: the forge build output, and a list mapping each applied fix to its finding id."
  run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$prompt" \
    || warn "v2 builder subagent failed"
}

phase4_verify() {
  log "Phase 4.8: 3-run forge test verification"
  require forge "https://book.getfoundry.sh"

  local workdir
  workdir="$(dirname "$TEST_DIR")"

  local run1="$workdir/run1.txt"
  local run2="$workdir/run2.txt"
  local run3="$workdir/run3.txt"

  log "Run 1: ExploitV1 (expected fail)"
  (cd "$workdir" && forge test --match-path 'test/ExploitV1*' -vvv 2>&1 || true) > "$run1"

  log "Run 2: ExploitV2 (expected pass)"
  (cd "$workdir" && forge test --match-path 'test/ExploitV2*' -vvv 2>&1 || true) > "$run2"

  log "Run 3: full suite"
  (cd "$workdir" && forge test -vvv 2>&1 || true) > "$run3"

  log "Consolidating report to $REPORT"
  {
    echo "# Solidity Audit Report"
    echo
    echo "Repo: $REPO"
    echo "Generated: $(date -Iseconds)"
    echo
    echo "## Run 1 (ExploitV1 expected fail)"
    echo
    echo '```'
    cat "$run1"
    echo '```'
    echo
    echo "## Run 2 (ExploitV2 expected pass)"
    echo
    echo '```'
    cat "$run2"
    echo '```'
    echo
    echo "## Run 3 (full suite)"
    echo
    echo '```'
    cat "$run3"
    echo '```'
    echo
    echo "## Summary"
    echo
    grep -E 'Suite result' "$run1" "$run2" "$run3"
  } > "$REPORT"

  ok "Report written to $REPORT"
  log "Summary:"
  grep 'Suite result' "$REPORT" || true
}

# Dispatcher ------------------------------------------------------------
case "$COMMAND" in
  init)      phase1_malware; phase2_read_code ;;
  scan)      phase1_malware; phase3_discovery ;;
  classify)  phase3_8_classify ;;
  reproduce) phase4_reproduce ;;
  fix)       phase4_fix ;;
  verify)    phase4_verify ;;
  all)
    phase1_malware
    phase2_read_code
    phase3_discovery
    phase3_8_classify
    phase4_reproduce
    phase4_fix
    phase4_verify
    ok "All phases complete. Report: $REPORT"
    ;;
  help|*)    show_help ;;
esac
