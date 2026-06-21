#!/bin/bash
# PostToolUse hook: bump build number, rebuild app if source changed, commit & push.

PLIST="/Users/cameron/ScrivenerReader/Info.plist"
REPO="/Users/cameron/ScrivenerReader"
LOG="$REPO/scripts/build.log"

FILE=$(jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

# ── 1. Bump CFBundleVersion (skip when Info.plist itself was edited) ──────────
if [[ "$FILE" != *"Info.plist"* ]]; then
    CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null | xargs)
    if [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((CURRENT + 1))" "$PLIST" 2>/dev/null
    fi
fi

# ── 2. Rebuild & redeploy when a source file changed ─────────────────────────
if [[ "$FILE" == *.swift || "$FILE" == *"Package.swift"* || "$FILE" == *"Info.plist"* ]]; then
    cd "$REPO"
    # Info.plist is embedded at link time — a clean build is needed to re-embed it.
    if [[ "$FILE" == *"Info.plist"* ]]; then
        swift package clean >> "$LOG" 2>&1
    fi
    bash "$REPO/build_app.sh" >> "$LOG" 2>&1
fi

# ── 3. Commit & push all changes ─────────────────────────────────────────────
cd "$REPO" && git add -A && git commit -m "auto: save changes" && git push
