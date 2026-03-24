#!/usr/bin/env bash

# Flatten All Script
# Searches .claude folders globally and recursively, extracting:
# - Plans (PLAN.md, plan.md, *-plan.md)
# - Tasks (*-tasks.md, TODO.md, tasks/)
# - dagRobin exports
# - Memory files (MEMORY.md, lessons.md)
# - Agent definitions
# - Skills
#
# Usage:
#   ./flatten-all.sh                    # Outputs to ./all-claude-plans.md
#   ./flatten-all.sh custom-output.md   # Custom output file
#   ./flatten-all.sh -p plans           # Only plans
#   ./flatten-all.sh -p tasks           # Only tasks
#   ./flatten-all.sh -p all             # Everything (default)
#   ./flatten-all.sh -p dagrobin        # Only dagRobin related

set -e

OUTPUT_FILE=""
FILTER="all"
SEARCH_ROOT="$HOME"

while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -p|--filter)
            FILTER="$2"
            shift 2
            ;;
        -r|--root)
            SEARCH_ROOT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -o, --output FILE    Output file (default: ./all-claude-plans.md)"
            echo "  -p, --filter TYPE   Filter: all, plans, tasks, memory, agents, skills, dagrobin"
            echo "  -r, --root PATH     Root directory to search (default: ~)"
            echo "  -h, --help          Show this help"
            exit 0
            ;;
        *)
            OUTPUT_FILE="$1"
            shift
            ;;
    esac
done

OUTPUT_FILE="${OUTPUT_FILE:-./all-claude-plans.md}"

# Find all .claude directories
CLAUDE_DIRS=()

# Global Claude
if [ -d "$HOME/.claude" ]; then
    CLAUDE_DIRS+=("$HOME/.claude")
fi

# Global OpenCode
if [ -d "$HOME/.config/opencode" ]; then
    CLAUDE_DIRS+=("$HOME/.config/opencode")
fi

# Walk up from current directory
CURRENT_DIR="$(pwd)"
while [ "$CURRENT_DIR" != "/" ]; do
    if [ -d "$CURRENT_DIR/.claude" ]; then
        CLAUDE_DIRS+=("$CURRENT_DIR/.claude")
    fi
    if [ -d "$CURRENT_DIR/.opencode" ]; then
        CLAUDE_DIRS+=("$CURRENT_DIR/.opencode")
    fi
    CURRENT_DIR="$(dirname "$CURRENT_DIR")"
done

# Find additional .claude folders under search root
while IFS= read -r -d '' dir; do
    CLAUDE_DIRS+=("$dir")
done < <(find "$SEARCH_ROOT" -maxdepth 4 -type d -name ".claude" 2>/dev/null -print0)

# Remove duplicates
IFS=$'\n' CLAUDE_DIRS=($(printf "%s\n" "${CLAUDE_DIRS[@]}" | sort -u))
unset IFS

# File patterns based on filter
declare -A PATTERNS
PATTERNS[plans]="*PLAN*.md *plan*.md *-plan.md TODO.md"
PATTERNS[tasks]="*-tasks.md *-task*.md tasks/*.md"
PATTERNS[memory]="*MEMORY*.md *memory*.md *lessons*.md"
PATTERNS[agents]=".claude/agents/*.md agents/*.md"
PATTERNS[skills]=".claude/skills/*.md skills/*.md .opencode/skills/*.md"
PATTERNS[dagrobin]="dagrobin.db *-paths.md *-steps.md *-estimative.md"
PATTERNS[all]="*.md *.mdx"

# Build find command
FIND_OPTS="-type f"

case $FILTER in
    plans)
        FIND_OPTS="$FIND_OPTS \( -name '*PLAN*' -o -name '*plan*' -o -name '*-plan*' -o -name 'TODO*' -o -name 'todo*' \)"
        ;;
    tasks)
        FIND_OPTS="$FIND_OPTS \( -name '*-tasks*' -o -name '*-task*' \)"
        ;;
    memory)
        FIND_OPTS="$FIND_OPTS \( -name '*MEMORY*' -o -name '*memory*' -o -name '*lessons*' \)"
        ;;
    agents)
        FIND_OPTS="$FIND_OPTS -path '*/agents/*.md'"
        ;;
    skills)
        FIND_OPTS="$FIND_OPTS -path '*/skills/*.md'"
        ;;
    dagrobin)
        FIND_OPTS="$FIND_OPTS \( -name '*-paths.md' -o -name '*-steps.md' -o -name '*-estimative.md' -o -name '*-plan*.md' \)"
        ;;
    all|*)
        FIND_OPTS="$FIND_OPTS -name '*.md' -o -name '*.mdx'"
        ;;
esac

# Start output
{
    echo "# Claude & OpenCode Consolidated Files"
    echo ""
    echo "**Generated:** $(date)"
    echo "**Filter:** $FILTER"
    echo "**Search paths:** ${#CLAUDE_DIRS[@]}"
    echo ""
    
    for dir in "${CLAUDE_DIRS[@]}"; do
        echo "---"
        echo ""
        echo "## 📁 $dir"
        echo ""
        
        # Find files in this directory
        while IFS= read -r -d '' file; do
            REL_PATH="${file#$HOME/}"
            echo "### 📄 $REL_PATH"
            echo ""
            echo '```markdown'
            cat "$file"
            echo '```'
            echo ""
        done < <(find "$dir" $FIND_OPTS 2>/dev/null -print0)
        
    done
    
    echo "---"
    echo ""
    echo "*End of consolidated output*"
    
} > "$OUTPUT_FILE"

echo "✅ Output saved to: $OUTPUT_FILE"
echo "📊 Total lines: $(wc -l < "$OUTPUT_FILE")"
echo "🔍 Searched ${#CLAUDE_DIRS[@]} directories"
