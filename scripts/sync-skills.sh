#!/usr/bin/env bash

# Sync Skills & Agents Script
# Usage: ./sync-skills.sh <paths-file>
#
# <paths-file> should contain one absolute path per line
# Example:
#   /Users/afa/Developer/project1
#   /Users/afa/Developer/project2
#   ~/.claude/skills
#   ~/.config/opencode/skills

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$PROJECT_ROOT/skills"
AGENTS_DIR="$PROJECT_ROOT/agents"
RULES_DIR="$PROJECT_ROOT/rules"
RESOURCES_DIR="$PROJECT_ROOT/resources"

if [ -z "$1" ]; then
    echo "Usage: $0 <paths-file>"
    echo ""
    echo "Example paths-file content:"
    echo "  /Users/afa/Developer/my-project"
    echo "  ~/.claude/skills"
    echo "  ~/.config/opencode/skills"
    exit 1
fi

PATHS_FILE="$1"

if [ ! -f "$PATHS_FILE" ]; then
    echo "Error: File '$PATHS_FILE' not found"
    exit 1
fi

echo "Syncing skills from:    $SKILLS_DIR"
echo "Syncing agents from:    $AGENTS_DIR"
echo "Syncing rules from:     $RULES_DIR"
echo "Syncing resources from: $RESOURCES_DIR"
echo "To paths listed in:     $PATHS_FILE"
echo ""

# --- Sync agents to ~/.claude/agents/ and ~/.config/opencode/agents/ ---
#
# The source files are Claude Code native: `tools: Read, Edit, Write, Bash`
# (a CSV allow-list) plus `model: sonnet`. OpenCode rejects that CSV outright
# ("Expected object | undefined, got ..."), so agents/ must NEVER be copied
# raw into an OpenCode config dir -- always run this script.
#
# OpenCode's `tools` key is @deprecated and, being an override map, a list of
# `true` entries restricts nothing anyway. We translate the allow-list into
# `permission:` denials instead, and only for the three gates that matter:
#   edit -> all file mutation (write/edit/patch)   bash -> shell   task -> subagents
# Tools the agent does have are left unset so the user's own defaults (often
# `ask` for bash) keep applying instead of being force-allowed.
if [ -d "$AGENTS_DIR" ]; then
    mkdir -p "$HOME/.claude/agents" "$HOME/.config/opencode/agents"

    for agent_file in "$AGENTS_DIR"/*.md; do
        [ -f "$agent_file" ] || continue
        agent_name=$(basename "$agent_file")

        # Claude Code: copy verbatim (CSV format is what it expects)
        cp "$agent_file" "$HOME/.claude/agents/$agent_name"
        echo "  [agent:claude]   $agent_name -> $HOME/.claude/agents/$agent_name"

        # OpenCode: drop `model:`, translate the `tools:` allow-list into `permission:` denials
        awk '
            /^model:/ { next } # Remove linhas model:
            /^tools:[[:space:]]/ && !done {
                done = 1
                line = $0
                sub(/^tools:[[:space:]]*/, "", line)
                n = split(line, parts, /[[:space:]]*,[[:space:]]*/)
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[i])
                    have[tolower(parts[i])] = 1
                }
                deny = ""
                if (!have["edit"] && !have["write"]) deny = deny "  edit: deny\n"
                if (!have["bash"])                   deny = deny "  bash: deny\n"
                if (!have["agent"] && !have["task"]) deny = deny "  task: deny\n"
                if (deny != "") printf "permission:\n%s", deny
                next
            }
            { print }
        ' "$agent_file" > "$HOME/.config/opencode/agents/$agent_name"
        echo "  [agent:opencode] $agent_name -> $HOME/.config/opencode/agents/$agent_name"
    done
    echo ""
fi

# --- Sync skills to target paths ---
# Names that are now agents (clean up from old skill locations)
AGENT_NAMES="orchestrator architect builder qa-evaluator code-reviewer project-manager summarizer-auditor"

while IFS= read -r target_path || [ -n "$target_path" ]; do
    # Skip empty lines and comments
    [[ -z "$target_path" || "$target_path" =~ ^# ]] && continue

    # Expand ~ to home directory
    target_path="${target_path/#\~/$HOME}"

    # If the path already ends in /skills, use it directly.
    # Otherwise, append /skills.
    if [[ "$target_path" == */skills ]]; then
        dest_base="$target_path"
    else
        dest_base="$target_path/skills"
    fi

    mkdir -p "$dest_base"

    # Copy each skill folder from skills/ (only valid skills, with SKILL.md)
    for skill in "$SKILLS_DIR"/*/; do
        if [ -d "$skill" ]; then
            skill_name=$(basename "$skill")

            # Only sync folders that contain a SKILL.md
            if [ ! -f "$skill/SKILL.md" ]; then
                echo "  [skip] $skill_name (no SKILL.md)"
                continue
            fi

            dest_skill="$dest_base/$skill_name"
            mkdir -p "$dest_skill"
            cp -r "$skill"/* "$dest_skill/"
            echo "  [skill] $skill_name -> $dest_skill"
        fi
    done

    # Clean up old agent entries from skill targets
    for agent_name in $AGENT_NAMES; do
        old_skill="$dest_base/$agent_name"
        if [ -d "$old_skill" ]; then
            rm -rf "$old_skill"
            echo "  [cleanup] removed old skill: $old_skill"
        fi
    done

    echo ""

done < "$PATHS_FILE"

# --- Sync global/CLAUDE.md to ~/.claude/CLAUDE.md ---
if [ -f "$PROJECT_ROOT/global/CLAUDE.md" ]; then
    cp "$PROJECT_ROOT/global/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    echo "  [global] CLAUDE.md -> $HOME/.claude/CLAUDE.md"
    echo ""
fi

# --- Sync rules/ to ~/.claude/rules/ and ~/.config/opencode/rules/ ---
if [ -d "$RULES_DIR" ]; then
    for dest_rules in "$HOME/.claude/rules" "$HOME/.config/opencode/rules"; do
        mkdir -p "$dest_rules"
        for rule_file in "$RULES_DIR"/*.md; do
            if [ -f "$rule_file" ]; then
                rule_name=$(basename "$rule_file")
                cp "$rule_file" "$dest_rules/$rule_name"
                echo "  [rule] $rule_name -> $dest_rules/$rule_name"
            fi
        done
    done
    echo ""
fi

# --- Sync resources/ to ~/.claude/resources/ and ~/.config/opencode/resources/ ---
if [ -d "$RESOURCES_DIR" ]; then
    for dest_resources in "$HOME/.claude/resources" "$HOME/.config/opencode/resources"; do
        mkdir -p "$dest_resources"
        for res_file in "$RESOURCES_DIR"/*; do
            if [ -f "$res_file" ]; then
                res_name=$(basename "$res_file")
                cp "$res_file" "$dest_resources/$res_name"
                echo "  [resource] $res_name -> $dest_resources/$res_name"
            fi
        done
    done
    echo ""
fi

# --- Sync opencode.json to ~/.config/opencode/ ---
#
# The project root opencode.json is the source of truth and stays deliberately
# tiny: it only sets `default_agent: "orchestrator"`. Agents are NOT registered
# here -- OpenCode auto-discovers every ~/.config/opencode/agents/<name>.md and
# derives the agent name from the filename, with `mode:` read from each file's
# own frontmatter. Listing them under `instructions:` would instead append all
# seven personas to the system prompt of every agent, which is what caused
# subagents to answer with a blurred, cross-contaminated identity.
if [ -f "$PROJECT_ROOT/opencode.json" ]; then
    OPENCODE_CONF_DIR="$HOME/.config/opencode"
    mkdir -p "$OPENCODE_CONF_DIR"
    cp "$PROJECT_ROOT/opencode.json" "$OPENCODE_CONF_DIR/opencode.json"
    echo "  [config] opencode.json -> $OPENCODE_CONF_DIR/opencode.json (default_agent=orchestrator)"
    echo ""
fi

echo "Done! Synced: agents -> ~/.claude/agents/ | global CLAUDE.md | skills | rules | resources | opencode.json"
