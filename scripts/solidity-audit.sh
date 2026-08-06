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
#   --src <path>              Path to contracts dir (default: <repo>/market/src)
#   --test <path>             Path to tests dir (default: <repo>/market/test)
#   --findings <path>         Path to findings dir (default: <repo>/findings)
#   --worktree <path>         Use an existing worktree (skip git mv)
#   --skip-malware            Skip Phase 1 (pure source repo)
#   --classes <list>          Comma-separated audit classes (default: L01-L25)
#   --model <name>            Model for opencode (default: opencode/big-pickle)
#   --agent <name>            Agent for opencode (default: orchestrator)
#   --reserve-factor          Include Compound v2 reserve factor in v2
#   --report <path>           Output report path (default: /tmp/v2-build-report.md)
#   --dry-run                 Print commands without running them
#   --verbose                 Print every command before running
#
# Example:
#   ./solidity-audit.sh all ~/work/myproject --reserve-factor --report ~/audit.md

set -euo pipefail

VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"

# Defaults
REPO=""
SRC=""
TEST_DIR=""
FINDINGS_DIR=""
WORKTREE=""
SKIP_MALWARE=0
CLASSES="L01,L02,L03,L04,L05,L06,L07,L08,L09,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25"
MODEL="opencode/big-pickle"
AGENT="orchestrator"
RESERVE_FACTOR=0
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
    --model)      MODEL="$2"; shift 2 ;;
    --agent)      AGENT="$2"; shift 2 ;;
    --reserve-factor) RESERVE_FACTOR=1; shift ;;
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
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

[ "$COMMAND" = "help" ] || [ "$COMMAND" = "--help" ] || [ "$COMMAND" = "-h" ] && show_help

[ -z "$COMMAND" ] && { err "No command. Run: $0 help"; exit 1; }
[ -z "$REPO" ] && { err "No <repo-path> provided."; exit 1; }

REPO="$(cd "$REPO" 2>/dev/null && pwd || echo "$REPO")"
[ -d "$REPO" ] || { err "Repo not found: $REPO"; exit 1; }

# Set defaults relative to repo
[ -z "$SRC" ]          && SRC="$REPO/market/src"
[ -z "$TEST_DIR" ]     && TEST_DIR="$REPO/market/test"
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

phase3_discovery() {
  log "Phase 3: multi-tool finding discovery"
  require opencode "https://opencode.ai"

  mkdir -p "$FINDINGS_DIR"

  # 3.1 — One opencode subagent per audit class (grouped to <=10)
  log "3.1 — dispatching opencode subagents for classes: $CLASSES"
  local IFS=','
  local -a cls=($CLASSES)
  local i=0
  local -a pids=()
  for class in "${cls[@]}"; do
    ((i++))
    local prompt="You are a Solidity security auditor. Audit $SRC for the following class:
$class: <describe this class, severity default, what to look for>
Read LendingMarket.sol and any related files in $SRC fully. Output markdown with: ID, severity, file:line, snippet, fix. Mark class N/A if no instances. Do NOT modify code."
    local outfile="$FINDINGS_DIR/opencode-${class}.md"
    run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$prompt" > "$outfile" 2>&1 &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do wait "$pid" || warn "subagent $pid failed"; done
  ok "opencode subagents done ($(ls "$FINDINGS_DIR"/opencode-*.md 2>/dev/null | wc -l) files)"

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
  require python3 "system"

  # 3.7 — Consolidate raw findings
  log "3.7 — consolidating raw findings into raw.json"
  python3 <<'PYEOF'
import json, re, sys
from pathlib import Path

findings_dir = Path("$FINDINGS_DIR")
raw = []
for path in sorted(findings_dir.glob("*.md")):
    if path.name == "claude.md" and path.stat().st_size == 0:
        continue
    content = path.read_text(encoding="utf-8", errors="replace")
    sections = re.split(r'\n##\s+', content)
    for sec in sections[1:]:
        first_line = sec.split('\n', 1)[0].strip()
        if not first_line:
            continue
        m = re.match(r'(?:Finding\s+)?([A-Z]\d+[\-\.][A-Z0-9]+|F-L\d+\-\d+|[A-Z]\d+\.[A-Z])\s+[—\-]\s*(.*)', first_line)
        if not m:
            continue
        fid = m.group(1)
        title = m.group(2).strip()
        raw.append({
            "source_file": path.stem,
            "finding_id": fid,
            "title": title,
            "file": None,
            "line": None,
            "summary": None,
        })
(findings_dir / "raw.json").write_text(json.dumps(raw, indent=2, ensure_ascii=False))
print(f"Wrote {len(raw)} findings to raw.json")
PYEOF

  # Dispatch 3 subagents in parallel
  log "Dispatching dedupe + ranker + patch-check (3 subagents in background)"

  local pids=()
  local dedup_prompt="You are a Solidity auditor doing semantic deduplication. INPUT: $FINDINGS_DIR/raw.json. TASK: Cluster findings by same root cause + same code location + same exploit path. Output JSON only with shape: {\"clusters\":[{\"canonical_id\":\"...\",\"member_ids\":[...],\"title\":\"...\",\"root_cause\":\"...\",\"severity\":\"...\",\"file\":\"...\",\"line\":N}],\"stats\":{...}}. Every input finding id appears exactly once. Choose canonical_id preferring opencode over slither."
  local ranker_prompt="You are a Solidity triager ranking canonical findings. INPUT: $FINDINGS_DIR/deduped.json. OUTPUT JSON only: {\"rankings\":[{\"canonical_id\":\"...\",\"rank\":1,\"impact_level\":\"Critical|High|Medium|Low|Info\",\"minimum_reward\":USD,\"maximum_reward\":USD,\"reasoning\":\"...\",\"root_bug\":\"...\"}],\"summary\":\"...\",\"missing_from_prompt\":\"...\"}. Compound-style norms: Critical \$25K-\$100K, High \$5K-\$25K, Medium \$1K-\$5K, Low \$0-\$500."
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

  # Extract JSONs
  python3 - "$FINDINGS_DIR" <<'PYEOF'
import json, re, sys
from pathlib import Path
findings_dir = Path(sys.argv[1])
for raw_name, json_name in [
    ("deduped.raw.txt", "deduped.json"),
    ("ranked.raw.txt", "ranked.json"),
    ("patch-status.raw.txt", "patch-status.json"),
]:
    raw_path = findings_dir / raw_name
    json_path = findings_dir / json_name
    if not raw_path.exists():
        print(f"WARN: {raw_path} missing")
        continue
    text = re.sub(r'\x1b\[[0-9;]*m', '', raw_path.read_text(encoding="utf-8", errors="replace"))
    # Find outermost JSON
    positions = [i for i, c in enumerate(text) if c == '{']
    for start in reversed(positions):
        depth = 0
        end = start
        for i, c in enumerate(text[start:]):
            if c == '{': depth += 1
            elif c == '}': depth -= 1
            if depth == 0:
                end = start + i + 1
                break
        try:
            data = json.loads(text[start:end])
            json_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
            print(f"OK {json_name}")
            break
        except json.JSONDecodeError:
            continue
    else:
        print(f"FAIL {raw_name} → no parseable JSON found")
PYEOF
}

phase4_reproduce() {
  log "Phase 4.2: write ExploitV1 tests, run them"
  require forge "https://book.getfoundry.sh"
  require python3 "system"

  # Find an opencode subagent that can write the tests
  require opencode "https://opencode.ai"

  log "Dispatching subagent to write ExploitV1.t.sol"
  local prompt="You are a Solidity QA engineer. Read $FINDINGS_DIR/deduped.json and $FINDINGS_DIR/FINDINGS-V2.md. Write $TEST_DIR/ExploitV1.t.sol with one test per shippable finding. Each test name starts with test_Exploit_<canonical_id>. Tests import LendingMarketV1 (preserved) and are written to FAIL — asserting a property the vulnerable code violates. Each test body has a 6-line comment block (canonical_id, severity, file:line, root_cause, INCLUDED/EXCLUDED justification). Use the test/LendingMarket.t.sol setup pattern. After writing, run: cd $(dirname $TEST_DIR) && forge test --match-path 'test/ExploitV1*' 2>&1 | tail -3. Report test count and pass/fail."
  run opencode run --model "$MODEL" --agent "$AGENT" --auto --pure "$prompt" \
    || warn "ExploitV1 subagent failed"

  log "Running ExploitV1 baseline"
  local out
  out=$(cd "$(dirname "$TEST_DIR")" && forge test --match-path 'test/ExploitV1*' 2>&1 || true)
  echo "$out" > "$REPO/market/baseline-v1.txt" 2>/dev/null || true
  echo "$out" | tail -5
}

phase4_fix() {
  log "Phase 4.4: build v2 with true-positive fixes"
  require opencode "https://opencode.ai"
  require forge "https://book.getfoundry.sh"

  local reserve_arg=""
  [ "$RESERVE_FACTOR" = 1 ] && reserve_arg="AND add Compound v2 reserve factor (reserveFactor, reserves, setReserveFactor, withdrawReserves)."

  log "Dispatching v2 builder subagent"
  local prompt="You are a senior Solidity engineer. Build v2 of the lending market. (1) Copy $SRC/LendingMarket.sol to $SRC/LendingMarketV1.sol (rename contract to LendingMarketV1). (2) Create new $SRC/LendingMarket.sol (v2) by copying V1, renaming back to LendingMarket, and applying fixes for the 14 TRUE-POSITIVE findings in $FINDINGS_DIR/FINDINGS-V2.md only. Use OpenZeppelin v5.x: ReentrancyGuard, SafeERC20, Initializable (with _disableInitializers in constructor), AccessControl. Add __gap[44]. (3) $reserve_arg (4) Update test/LendingMarket.t.sol, test/Exploit.t.sol, script/Deploy.s.sol to import from V1 paths. (5) cd $(dirname $SRC) && forge build to confirm zero errors. (6) Run: cd $(dirname $TEST_DIR) && forge test --match-path 'test/ExploitV1*' 2>&1 | tail -3 and confirm v1 tests still fail as expected. Report forge build output and the list of 14 fixes applied."
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
