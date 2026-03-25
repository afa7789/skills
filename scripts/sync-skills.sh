#!/usr/bin/env bash

# Sync Skills Script
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
SKILLS_DIR="$(dirname "$SCRIPT_DIR")"

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

echo "Syncing skills from: $SKILLS_DIR"
echo "To paths listed in: $PATHS_FILE"
echo ""

while IFS= read -r target_path || [ -n "$target_path" ]; do
    # Skip empty lines and comments
    [[ -z "$target_path" || "$target_path" =~ ^# ]] && continue

    # Expand ~ to home directory
    target_path="${target_path/#\~/$HOME}"

    # Determine destination based on path
    if [[ "$target_path" == *".claude/skills"* ]]; then
        # Copy to .claude/skills/<skill-name>/
        dest_base="${target_path%/.claude/skills}"
        dest_base="$dest_base/.claude/skills"
    elif [[ "$target_path" == *".opencode/skills"* ]]; then
        # Copy to .opencode/skills/<skill-name>/
        dest_base="${target_path%/.opencode/skills}"
        dest_base="$dest_base/.opencode/skills"
    else
        # Default: copy to <path>/skills/<skill-name>/
        dest_base="$target_path/skills"
    fi

    # Create destination if it doesn't exist
    mkdir -p "$dest_base"

    # Copy each skill folder
    for skill in "$SKILLS_DIR"/*/; do
        if [ -d "$skill" ]; then
            skill_name=$(basename "$skill")
            dest_skill="$dest_base/$skill_name"
            
            mkdir -p "$dest_skill"
            cp -r "$skill"/* "$dest_skill/"
            echo "✓ Copied $skill_name to $dest_skill"
        fi
    done

    echo ""

done < "$PATHS_FILE"

echo "Done! Skills synced to all paths."
