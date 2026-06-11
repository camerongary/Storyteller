#!/bin/bash
# Called by the Claude Code PostToolUse hook after every Write/Edit.
# Increments CFBundleVersion in Info.plist (unless Info.plist itself was just edited),
# then commits and pushes all changes.

PLIST="/Users/cameron/ScrivenerReader/Info.plist"
REPO="/Users/cameron/ScrivenerReader"

# Parse the edited file path from the hook's stdin JSON payload
FILE=$(jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# Bump build number — but not when Info.plist itself was edited (avoids a loop)
if [[ "$FILE" != *"Info.plist"* ]]; then
    CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null | xargs)
    if [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((CURRENT + 1))" "$PLIST" 2>/dev/null
    fi
fi

cd "$REPO" && git add -A && git commit -m "auto: save changes" && git push
