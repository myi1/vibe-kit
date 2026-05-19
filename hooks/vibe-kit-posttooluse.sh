#!/usr/bin/env bash
# vibe-kit-posttooluse.sh — Claude Code PostToolUse hook (v0.6+).
#
# Silent file-change logger. Fires after every Write/Edit/MultiEdit/NotebookEdit
# tool call. Appends the touched file path to a per-project log so the
# UserPromptSubmit hook can nudge Claude at the start of the NEXT turn to
# consider syncing gbrain / updating taskmaster.
#
# Output: nothing. This hook never speaks to Claude directly.
# Latency cost: ~1ms (one append to a local file).
#
# Disable paths (in order of precedence):
#   1. ENV  GBRAIN_PER_TURN_SYNC=never                 (per-shell, immediate)
#   2. ~/.vibe-kit/config.json  per_turn_sync=never    (global)
#   3. .vibe-kit-version  per_turn_sync=never          (per-repo)
#   default: "on_changes" (log every write, nudge on next prompt)
#
# Bash 3.2+ compatible.

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

[ -f .vibe-kit-version ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Resolve mode (env > global > per-repo > default)
mode="${GBRAIN_PER_TURN_SYNC:-}"
if [ -z "$mode" ] && [ -f "$HOME/.vibe-kit/config.json" ]; then
  mode=$(jq -r '.per_turn_sync // ""' "$HOME/.vibe-kit/config.json" 2>/dev/null)
fi
if [ -z "$mode" ]; then
  mode=$(jq -r '.per_turn_sync // "on_changes"' .vibe-kit-version 2>/dev/null)
fi
[ "$mode" = "never" ] && exit 0

# Resolve project_key
project_key=$(jq -r '.project_key // ""' .vibe-kit-version 2>/dev/null)
[ -z "$project_key" ] || [ "$project_key" = "null" ] && project_key=$(basename "$PROJECT_DIR")

# Parse hook stdin payload — Claude Code sends JSON describing the tool call
payload=$(cat 2>/dev/null || echo '{}')

tool_name=$(echo "$payload" | jq -r '.tool_name // ""' 2>/dev/null)
case "$tool_name" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
[ -z "$file_path" ] || [ "$file_path" = "null" ] && exit 0

# Append to the per-project pending-syncs log
log_dir="$HOME/.vibe-kit/projects/$project_key/.pending-syncs"
mkdir -p "$log_dir" 2>/dev/null || exit 0
echo "$(date +%s) $file_path" >> "$log_dir/changes.log" 2>/dev/null || true
exit 0
