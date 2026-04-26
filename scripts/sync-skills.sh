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

# --- Sync agents to ~/.claude/agents/ ---
if [ -d "$AGENTS_DIR" ]; then
    AGENTS_DEST="$HOME/.claude/agents"
    mkdir -p "$AGENTS_DEST"

    for agent_file in "$AGENTS_DIR"/*.md; do
        if [ -f "$agent_file" ]; then
            agent_name=$(basename "$agent_file")
            cp "$agent_file" "$AGENTS_DEST/$agent_name"
            echo "  [agent] $agent_name -> $AGENTS_DEST/$agent_name"
        fi
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

# --- Generate opencode.json in ~/.config/opencode/ ---
if [ -d "$AGENTS_DIR" ]; then
    OPENCODE_CONF_DIR="$HOME/.config/opencode"
    mkdir -p "$OPENCODE_CONF_DIR"
    OPENCODE_JSON="$OPENCODE_CONF_DIR/opencode.json"

    echo "{" > "$OPENCODE_JSON"
    echo "  \"subagents\": {" >> "$OPENCODE_JSON"
    
    first=true
    for agent_file in "$AGENTS_DIR"/*.md; do
        if [ -f "$agent_file" ]; then
            agent_name=$(basename "$agent_file" .md)
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> "$OPENCODE_JSON"
            fi
            echo -n "    \"$agent_name\": \"agents/$(basename "$agent_file")\"" >> "$OPENCODE_JSON"
        fi
    done
    echo "" >> "$OPENCODE_JSON"
    echo "  }" >> "$OPENCODE_JSON"
    echo "}" >> "$OPENCODE_JSON"

    echo "  [config] Generated opencode.json -> $OPENCODE_JSON"
    echo ""
fi

echo "Done! Synced: agents -> ~/.claude/agents/ | global CLAUDE.md | skills | rules | resources | opencode.json"
