#!/usr/bin/env bash
# vibe-kit-userpromptsubmit.sh — Claude Code UserPromptSubmit hook (v0.6+).
#
# Per-turn auto-update nudge. Fires when the user submits a new prompt.
# Reads the pending-syncs log (populated by the PostToolUse hook on
# Write/Edit/MultiEdit/NotebookEdit). If files have changed since the last
# turn, injects a soft nudge into Claude's context for THIS turn:
#   "Files changed: X, Y, Z. If any in-progress taskmaster task is done,
#    mark it. If markdown changed, gbrain sync."
#
# Then truncates the log so the same change set isn't nudged twice.
#
# This is NOT a forced action — it's a context line. Claude reads it,
# makes a judgment, acts if relevant or skips silently. If you find it
# bothersome, disable via the same 3 paths as the PostToolUse hook:
#   GBRAIN_PER_TURN_SYNC=never (env, immediate)
#   ~/.vibe-kit/config.json   per_turn_sync=never (global)
#   .vibe-kit-version         per_turn_sync=never (per-repo)
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

log_file="$HOME/.vibe-kit/projects/$project_key/.pending-syncs/changes.log"
[ -f "$log_file" ] || exit 0
[ -s "$log_file" ] || exit 0

# Read + dedupe paths (cap at 20 for context budget)
files=$(awk '{$1=""; sub(/^ /, ""); print}' "$log_file" | sort -u | head -20)
file_count=$(echo "$files" | grep -c . 2>/dev/null || echo 0)
[ "$file_count" = "0" ] && exit 0

# Detect actionable hint surfaces. If neither taskmaster nor gbrain applies,
# skip the nudge entirely — no point telling Claude "files changed" if no
# concrete action is available.
hints=""
if [ -d .taskmaster ] && command -v task-master >/dev/null 2>&1; then
  # grep -c on empty input emits "0" AND exits non-zero. Don't `|| echo 0`
  # (would append a second "0"). Just trust grep's stdout, default to 0.
  in_progress=$(task-master list --status=in-progress 2>/dev/null | grep -cE '^\| *[0-9]' 2>/dev/null)
  in_progress=${in_progress:-0}
  in_progress=$(echo "$in_progress" | tr -dc '0-9')
  [ -z "$in_progress" ] && in_progress=0
  if [ "$in_progress" -gt 0 ] 2>/dev/null; then
    hints="${hints}  - Taskmaster: $in_progress task(s) in-progress. If you finished one this turn, mark it done (\`task-master set-status <id> done\`).
"
  fi
fi
if command -v gbrain >/dev/null 2>&1; then
  if gbrain sources list 2>/dev/null | grep -F "$PROJECT_DIR" >/dev/null 2>&1; then
    # Did any .md files change? gbrain only cares about markdown.
    md_changed=$(echo "$files" | grep -c '\.md$' 2>/dev/null)
    md_changed=${md_changed:-0}
    md_changed=$(echo "$md_changed" | tr -dc '0-9')
    [ -z "$md_changed" ] && md_changed=0
    if [ "$md_changed" -gt 0 ] 2>/dev/null; then
      hints="${hints}  - gbrain: $md_changed markdown file(s) changed. Consider \`gbrain sync\` so search stays current.
"
    fi
  fi
fi

# Truncate log regardless — we don't want stale changes to keep nudging.
: > "$log_file" 2>/dev/null || true

if [ -z "$hints" ]; then
  exit 0
fi

# Build the context message (kept short — competes for context budget)
context_msg=$(cat <<EOF
[vibe-kit per-turn check] ${file_count} file(s) changed since last turn:
$(echo "$files" | sed 's/^/  - /' | head -10)$([ "$file_count" -gt 10 ] && echo "
  ... and $((file_count - 10)) more")

Soft nudges (act only if relevant — these are reminders, not commands):
${hints}
(disable: export GBRAIN_PER_TURN_SYNC=never, or set per_turn_sync=never in .vibe-kit-version)
EOF
)

# JSON-escape and emit Claude Code hook output format
escaped=$(printf '%s' "$context_msg" | jq -Rs .)
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $escaped
  }
}
EOF
exit 0
