#!/usr/bin/env bash
# vibe-kit-session-start.sh — Claude Code SessionStart hook.
#
# Runs at the start of every Claude Code session. If the current working
# directory is a vibe-kit-retrofitted repo (has .vibe-kit-version), emits
# a compact briefing to stdout which Claude Code injects into the session
# context. Silent no-op for non-retrofitted repos.
#
# v0.2.0: the reference layer (gstack-learnings, design docs, ceo plans,
# handoffs) lives OUTSIDE the repo at ~/.vibe-kit/projects/<project_key>/
# so this hook works regardless of which branch is checked out. Pre-v0.2
# brains that still have docs/vibe-kit/reference/ inside the repo are
# detected and the hook falls back to that location (with a one-line
# nudge to run `vibe-retrofit migrate-to-global`).
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
# Keep this concise (≤35 lines) — it's injected into every session and
# competes for context budget.

repo=$(basename "$PROJECT_DIR")
ver=$(jq -r '.vibe_kit_version // "?"' .vibe-kit-version 2>/dev/null)
tier=$(jq -r '.tier // "?"' .vibe-kit-version 2>/dev/null)
when=$(jq -r '.retrofitted_at // "?"' .vibe-kit-version 2>/dev/null)
project_key=$(jq -r '.project_key // ""' .vibe-kit-version 2>/dev/null)

# v0.2.0 reference-dir resolution.
# Precedence: explicit global_reference_dir in .vibe-kit-version >
#             ~/.vibe-kit/projects/<project_key>/reference >
#             ~/.vibe-kit/projects/<basename-cwd>/reference >
#             in-repo docs/vibe-kit/reference (pre-v0.2 fallback).
REF_DIR=""
ref_explicit=$(jq -r '.global_reference_dir // ""' .vibe-kit-version 2>/dev/null)
if [ -n "$ref_explicit" ] && [ "$ref_explicit" != "null" ]; then
  # Expand leading ~/ (jq won't do shell expansion).
  ref_explicit="${ref_explicit/#\~\//$HOME/}"
  [ -d "$ref_explicit" ] && REF_DIR="$ref_explicit"
fi
if [ -z "$REF_DIR" ]; then
  key_for_path="${project_key:-$repo}"
  candidate="$HOME/.vibe-kit/projects/$key_for_path/reference"
  [ -d "$candidate" ] && REF_DIR="$candidate"
fi
LEGACY_IN_REPO=""
if [ -z "$REF_DIR" ] && [ -d "docs/vibe-kit/reference" ]; then
  REF_DIR="docs/vibe-kit/reference"
  LEGACY_IN_REPO="yes"
fi

cat <<EOF
[vibe-kit session-start briefing for ${repo}]
This repo was retrofitted with vibe-kit v${ver} (tier ${tier}) on ${when}.
Project key: ${project_key:-${repo}}.
Reference layer: ${REF_DIR:-"(none found — run \`vibe-retrofit tier 2\` from this repo)"}.

Per CLAUDE.md's Session Start Ritual, read:
EOF

if [ -n "$REF_DIR" ]; then
  cat <<EOF
  - ${REF_DIR}/gstack-learnings.md (institutional knowledge)
  - ${REF_DIR}/gstack-designs/    (prior design docs)
  - ${REF_DIR}/gstack-ceo-plans/  (CEO plans)
  - KNOWN_GOTCHAS.md              (project quirks, branch-coupled)
EOF
else
  echo "  - KNOWN_GOTCHAS.md              (project quirks, branch-coupled)"
fi

if [ -n "$LEGACY_IN_REPO" ]; then
  echo ""
  echo "  NOTE: this repo still uses the v0.1 in-repo reference layout. That breaks"
  echo "  whenever a fresh session opens on a branch that hasn't merged the retrofit."
  echo "  Run \`vibe-retrofit migrate-to-global\` from this repo to move the reference"
  echo "  layer to ~/.vibe-kit/projects/${project_key:-$repo}/ (one-shot, idempotent)."
fi

echo ""
echo "Before responding to the user's first request:"

# Learnings summary
LEARNINGS_FILE="${REF_DIR}/gstack-learnings.md"
if [ -n "$REF_DIR" ] && [ -f "$LEARNINGS_FILE" ]; then
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
HANDOFFS_DIR="${REF_DIR}/gstack-handoffs"
if [ -n "$REF_DIR" ] && [ -d "$HANDOFFS_DIR" ]; then
  recent_handoff=$(ls -t "$HANDOFFS_DIR"/*.md 2>/dev/null | head -1)
  if [ -n "$recent_handoff" ]; then
    echo "  - Recent handoff: $(basename "$recent_handoff")"
  fi
fi

# Recent CEO plan (often the most-current "what are we building" signal)
CEO_DIR="${REF_DIR}/gstack-ceo-plans"
if [ -n "$REF_DIR" ] && [ -d "$CEO_DIR" ]; then
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
