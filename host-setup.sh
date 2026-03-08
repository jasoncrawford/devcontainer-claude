#!/bin/bash
# Run this once on the host before starting the devcontainer for the first time.
# Safe to re-run — all operations are idempotent.
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
ok=true

mkdir -p "$CLAUDE_DIR/skills"
mkdir -p "$CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_DIR/projects"

# settings.json must be a file, not a directory — Docker will create a directory
# if it doesn't exist, which causes Claude to fail to read its settings.
if [ -d "$CLAUDE_DIR/settings.json" ]; then
    echo "ERROR: $CLAUDE_DIR/settings.json is a directory, not a file."
    echo "       This was likely created by Docker when the file was missing."
    echo "       Fix: rmdir '$CLAUDE_DIR/settings.json' then re-run this script."
    ok=false
elif [ ! -f "$CLAUDE_DIR/settings.json" ]; then
    echo '{}' > "$CLAUDE_DIR/settings.json"
    echo "Created $CLAUDE_DIR/settings.json"
fi

if [ "$ok" = false ]; then
    exit 1
fi

echo "Host setup complete. Ready to start the devcontainer."
