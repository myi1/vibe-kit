#!/usr/bin/env bash
# vibe-kit-session-start.sh — Claude Code SessionStart hook.
#
# Runs at the start of every Claude Code session. If the current working
# directory is a vibe-kit-retrofitted repo (has .vibe-kit-version), emits
# a compact briefing to stdout which Claude Code injects into the session
# context. Silent no-op for non-retrofitted repos.
#
# To wire into Claude Code: `bash ~/dev/vibe-kit/bin/install.sh --enable-hook`
# Or manually add to ~/.claude/settings.json:
#   {
#     "hooks": {
#       "SessionStart": [{
#         "matcher": "startup",
#         "hooks": [{ "type": "command", "command": "/Users/<you>/.claude/hooks/vibe-kit-session-start.sh" }]
#       }]
#     }
#   }
#
# Bash 3.2+ compatible. Stdout is what gets injected into Claude's context;
# stderr is silent / for debugging.

set -u

# Hooks may execute with cwd = the user's project, or sometimes their home.
# Resolve via $CLAUDE_PROJECT_DIR (set by Claude Code) or fall back to $PWD.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

# No-op if not a vibe-kit retrofitted repo.
[ -f .vibe-kit-version ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Output: a compact briefing that Claude reads as initial context.
# Keep this concise (≤30 lines) — it's injected into every session and
# competes for context budget.

repo=$(basename "$PROJECT_DIR")
ver=$(jq -r '.vibe_kit_version // "?"' .vibe-kit-version 2>/dev/null)
tier=$(jq -r '.tier // "?"' .vibe-kit-version 2>/dev/null)
when=$(jq -r '.retrofitted_at // "?"' .vibe-kit-version 2>/dev/null)

cat <<EOF
[vibe-kit session-start briefing for ${repo}]
This repo was retrofitted with vibe-kit v${ver} (tier ${tier}) on ${when}.

Per CLAUDE.md's Session Start Ritual, read:
  - docs/vibe-kit/reference/gstack-learnings.md (institutional knowledge)
  - docs/vibe-kit/reference/gstack-designs/    (prior design docs)
  - docs/vibe-kit/reference/gstack-ceo-plans/  (CEO plans)
  - KNOWN_GOTCHAS.md                            (project quirks)

Before responding to the user's first request:
EOF

# Learnings summary
LEARNINGS_FILE="docs/vibe-kit/reference/gstack-learnings.md"
if [ -f "$LEARNINGS_FILE" ]; then
  entries=$(grep -c "^## " "$LEARNINGS_FILE" 2>/dev/null || echo 0)
  echo "  - ${entries} learnings logged. Highest-confidence entries:"
  grep "^## " "$LEARNINGS_FILE" 2>/dev/null | head -3 | sed 's/^## /      • /'
fi

# Taskmaster summary (don't actually call task-master here — it's slow + may
# need an API key. Just signal presence so Claude knows to query it.)
if [ -d .taskmaster ]; then
  echo "  - Taskmaster is initialized. Run \`task-master next\` to see pending work."
fi

# Recent handoff (if within 14 days, it's likely "where we left off")
HANDOFFS_DIR="docs/vibe-kit/reference/gstack-handoffs"
if [ -d "$HANDOFFS_DIR" ]; then
  recent_handoff=$(ls -t "$HANDOFFS_DIR"/*.md 2>/dev/null | head -1)
  if [ -n "$recent_handoff" ]; then
    echo "  - Recent handoff: $(basename "$recent_handoff")"
  fi
fi

# Recent CEO plan (often the most-current "what are we building" signal)
CEO_DIR="docs/vibe-kit/reference/gstack-ceo-plans"
if [ -d "$CEO_DIR" ]; then
  recent_ceo=$(ls -t "$CEO_DIR"/*.md 2>/dev/null | head -1)
  if [ -n "$recent_ceo" ]; then
    echo "  - Most-recent CEO plan: $(basename "$recent_ceo")"
  fi
fi

echo ""
echo "Quote relevant learnings (by key) when you apply them. Skip the ritual"
echo "only if the user explicitly says so — every skip risks reintroducing"
echo "a documented pitfall."
echo "[/vibe-kit session-start briefing]"
