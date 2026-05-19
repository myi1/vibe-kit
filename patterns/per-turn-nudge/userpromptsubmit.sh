#!/usr/bin/env bash
# per-turn-nudge/userpromptsubmit.sh — Pattern 1's nudge injector.
#
# Adopt-and-rename version of vibe-kit's hook. Workspace-memory shops:
# parameterized via env vars, no .vibe-kit-version dependency.
#
# Reads the change log written by posttooluse.sh; if non-empty AND there
# are actionable hints, emits a soft context line for the current turn
# via hookSpecificOutput.additionalContext, then truncates the log.
#
# See: docs/PATTERNS.md#pattern-1 + patterns/per-turn-nudge/README.md
#
# Bash 3.2+ compatible.

set -u

[ "${NUDGE_DISABLE:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

STATE_DIR="${NUDGE_STATE_DIR:-$HOME/.local/state/per-turn-nudge}"
LOG_FILE="$STATE_DIR/changes.log"
[ -f "$LOG_FILE" ] || exit 0
[ -s "$LOG_FILE" ] || exit 0

# Read + dedupe paths (cap at 20 for context budget)
files=$(awk '{$1=""; sub(/^ /, ""); print}' "$LOG_FILE" | sort -u | head -20)
file_count=$(echo "$files" | grep -c . 2>/dev/null || echo 0)
[ "$file_count" = "0" ] && exit 0

# Build hints from configurable surfaces.
# Convention: each hint script reads file paths from stdin (one per line)
# and emits zero or more hint lines starting with `  - ` on stdout.
hints=""

# Built-in: taskmaster (Pattern 1's reference hint #1)
if [ "${NUDGE_HINT_TASKMASTER:-auto}" != "0" ] && [ -d .taskmaster ] && command -v task-master >/dev/null 2>&1; then
  in_progress=$(task-master list --status=in-progress 2>/dev/null | grep -cE '^\| *[0-9]' 2>/dev/null)
  in_progress=${in_progress:-0}
  in_progress=$(echo "$in_progress" | tr -dc '0-9')
  [ -z "$in_progress" ] && in_progress=0
  if [ "$in_progress" -gt 0 ] 2>/dev/null; then
    hints="${hints}  - Taskmaster: $in_progress task(s) in-progress. If you finished one this turn, mark it done.
"
  fi
fi

# Built-in: gbrain (Pattern 1's reference hint #2)
if [ "${NUDGE_HINT_GBRAIN:-auto}" != "0" ] && command -v gbrain >/dev/null 2>&1; then
  if gbrain sources list 2>/dev/null | grep -F "$(pwd)" >/dev/null 2>&1; then
    md_changed=$(echo "$files" | grep -c '\.md$' 2>/dev/null)
    md_changed=${md_changed:-0}
    md_changed=$(echo "$md_changed" | tr -dc '0-9')
    [ -z "$md_changed" ] && md_changed=0
    if [ "$md_changed" -gt 0 ] 2>/dev/null; then
      hints="${hints}  - gbrain: $md_changed markdown file(s) changed. Consider gbrain sync so search stays current.
"
    fi
  fi
fi

# Extension point: NUDGE_HINT_CUSTOM_CMD (Pattern 1's "custom surfaces")
if [ -n "${NUDGE_HINT_CUSTOM_CMD:-}" ] && [ -x "$NUDGE_HINT_CUSTOM_CMD" ]; then
  custom=$(echo "$files" | "$NUDGE_HINT_CUSTOM_CMD" 2>/dev/null)
  if [ -n "$custom" ]; then
    hints="${hints}${custom}
"
  fi
fi

# Truncate log regardless — stale changes shouldn't keep nudging.
: > "$LOG_FILE" 2>/dev/null || true

[ -z "$hints" ] && exit 0

# Build the context message (kept short — competes for context budget)
context_msg=$(cat <<EOF
[per-turn check] ${file_count} file(s) changed since last turn:
$(echo "$files" | sed 's/^/  - /' | head -10)$([ "$file_count" -gt 10 ] && echo "
  ... and $((file_count - 10)) more")

Soft nudges (act only if relevant — these are reminders, not commands):
${hints}
(disable: export NUDGE_DISABLE=1)
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
