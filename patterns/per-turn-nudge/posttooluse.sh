#!/usr/bin/env bash
# per-turn-nudge/posttooluse.sh — Pattern 1's silent file-change logger.
#
# Adopt-and-rename version of vibe-kit's hook. Workspace-memory shops:
# parameterized via env vars, no .vibe-kit-version dependency.
#
# Output: nothing. Latency: ~1ms (one file append).
#
# See: docs/PATTERNS.md#pattern-1 + patterns/per-turn-nudge/README.md
#
# Bash 3.2+ compatible.

set -u

[ "${NUDGE_DISABLE:-}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Configurable state dir. Default follows XDG-ish convention.
STATE_DIR="${NUDGE_STATE_DIR:-$HOME/.local/state/per-turn-nudge}"

# Parse hook stdin payload
payload=$(cat 2>/dev/null || echo '{}')
tool_name=$(echo "$payload" | jq -r '.tool_name // ""' 2>/dev/null)
case "$tool_name" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)
[ -z "$file_path" ] || [ "$file_path" = "null" ] && exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
echo "$(date +%s) $file_path" >> "$STATE_DIR/changes.log" 2>/dev/null || true
exit 0
