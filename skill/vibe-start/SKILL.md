---
name: vibe-start
description: The deterministic session-start ritual for vibe-kit-retrofitted repos. Reads `docs/vibe-kit/reference/gstack-learnings.md`, runs `task-master next` if Taskmaster is initialized, lists recent design + CEO-plan + handoff docs, and outputs a structured "ready briefing". Use when the user types `/vibe-start`, asks "what's the state of this repo", "where did we leave off", "what should I know before starting", or any time you're entering a new Claude Code session on a repo that has `.vibe-kit-version`.
---

# /vibe-start

The deterministic answer to "what should I know to be useful in this repo right now."

This skill runs a sequence of read-only commands and produces a single scannable briefing. It does NOT mutate anything. Think of it as the explicit, on-demand version of the imperative "Session start ritual" section that the `vibe-kit` CLAUDE.md template injects — if the user invokes this skill, they want the ritual run explicitly rather than relying on you to remember to do it.

## Phase 1 — Pre-flight (run first, stop on failure)

```bash
if [ ! -f .vibe-kit-version ]; then
  echo "ERROR: not a vibe-kit-retrofitted repo (.vibe-kit-version missing)."
  echo "  Run: vibe-retrofit tier 2  (from this directory)"
  echo "  Or: visit github.com/myi1/vibe-kit for install instructions."
  exit 1
fi
echo "=== vibe-kit metadata ==="
jq -r '"version: \(.vibe_kit_version)\ntier: \(.tier)\nretrofitted: \(.retrofitted_at)"' .vibe-kit-version
echo ""
```

If pre-flight fails: stop, tell the user this repo isn't retrofitted, suggest the fix, and end the skill. Do NOT proceed to other phases.

## Phase 2 — Load learnings

```bash
LEARNINGS_FILE="docs/vibe-kit/reference/gstack-learnings.md"
if [ -f "$LEARNINGS_FILE" ]; then
  entry_count=$(grep -c "^## " "$LEARNINGS_FILE" || echo 0)
  echo "=== Learnings: $entry_count entries ==="
  echo "Top 5 by confidence:"
  grep -E "^## .* confidence [0-9]+/10" "$LEARNINGS_FILE" | head -5
  echo ""
  echo "Full file at $LEARNINGS_FILE"
else
  echo "=== Learnings: none (no $LEARNINGS_FILE) ==="
  echo "Run \`vibe-retrofit tier 2\` to scaffold."
fi
echo ""
```

For each top-5 learning, you (Claude) should mentally bookmark the key. If the user's first real request touches any system area these learnings reference, quote the relevant entry's key in your reply.

## Phase 3 — Check Taskmaster

```bash
if [ -d .taskmaster ] && command -v task-master >/dev/null 2>&1; then
  echo "=== Pending tasks ==="
  task-master next 2>&1 | head -25
  echo ""
  pending_count=$(task-master list --status=pending 2>/dev/null | grep -cE "^\| +[0-9]" || echo "?")
  echo "Total pending: $pending_count"
else
  echo "=== Tasks: no Taskmaster ==="
  if [ -f TODOS.md ]; then
    echo "Falling back to TODOS.md ($(wc -l < TODOS.md) lines):"
    head -10 TODOS.md
  elif [ -f TODO.md ]; then
    echo "Falling back to TODO.md ($(wc -l < TODO.md) lines):"
    head -10 TODO.md
  else
    echo "No task surface detected. The user's pending work lives in their head (or GitHub Issues)."
  fi
fi
echo ""
```

## Phase 4 — Recent designs / CEO plans / handoffs

```bash
echo "=== Recent design docs (top 5 by mtime) ==="
ls -t docs/vibe-kit/reference/gstack-designs/*.md 2>/dev/null | head -5 || echo "(none)"
echo ""
echo "=== CEO plans ==="
ls -t docs/vibe-kit/reference/gstack-ceo-plans/*.md 2>/dev/null | head -5 || echo "(none)"
echo ""
echo "=== Handoff notes (recent) ==="
ls -t docs/vibe-kit/reference/gstack-handoffs/*.md 2>/dev/null | head -3 || echo "(none)"
echo ""
```

If a handoff note exists and is recent (within 7 days), read it — it's the most likely place "where we left off" is recorded.

## Phase 4.5 — Board state (v0.10.0)

Surface the unified board so the briefing includes a live picture of what's in flight / pending / landed across all task surfaces. This is drift detection at session start.

```bash
vibe-retrofit board --json 2>/dev/null | jq -r '
  "Board: " +
  ([.columns[] | "\(.name)=\(.items|length)"] | join(", "))
' 2>/dev/null || echo "Board: (unavailable)"
```

If any column has a notably high count (e.g. many in-flight, or PRs sitting in pending-review), call it out in the briefing — that's the drift signal ("3 in-flight tasks, 2 PRs pending review since >3 days"). For the full visual, mention: `vibe-retrofit board` opens the live kanban.

## Phase 5 — KNOWN_GOTCHAS quick check

```bash
if [ -f KNOWN_GOTCHAS.md ]; then
  echo "=== KNOWN_GOTCHAS.md: $(wc -l < KNOWN_GOTCHAS.md) lines ==="
  echo "(Sections present:)"
  grep "^## " KNOWN_GOTCHAS.md
fi
```

## Phase 6 — Output the briefing

Synthesize everything above into ONE scannable briefing for the user. Aim for ~15 lines. Format:

```
vibe-kit ready briefing for <repo-name>
========================================
Retrofitted: <date> at tier <N> (vibe-kit v<version>)

Learnings loaded: <N> entries. Top 3:
  - <KEY> (10/10): <one-line summary of insight>
  - <KEY> (10/10): <one-line summary>
  - <KEY> (10/10): <one-line summary>

Tasks: <N> pending. Next up: <task title> (id=<n>)
  OR
Tasks: no Taskmaster; <N> items in TODOS.md
  OR
Tasks: no tracker — user uses GitHub Issues or their head

Recent design context:
  - <date> — <slug> (<one-line topic if you can infer from filename>)
  - <date> — <slug>

KNOWN_GOTCHAS sections: <list section names>

Recent handoff: <filename> — <one-line topic if you can infer>

Ready. What do you want to work on?
```

End with the exact phrase **"What do you want to work on?"** — this is the cue that hands control back to the user with full context loaded.

## Posture

- Read-only. Never mutates.
- If the user's request after the briefing relates to one of the loaded learnings or designs, quote the key by name in your reply (proves you actually used what you loaded).
- Don't paste entire docs into the briefing. Filenames + counts + top-3 highlights. The user can ask to read more.
- If gbrain MCP is available (`mcp__gbrain__*` tools listed), also note: "Semantic search across past work available via gbrain." But don't auto-query — wait for the user's request.

## Completion

Report DONE after the briefing is delivered AND you've ended with "What do you want to work on?"

Report BLOCKED if pre-flight failed (not a retrofitted repo). Suggest `vibe-retrofit tier 2`.

## Bug detection (v0.8.0)

If `.vibe-kit-version` exists but `jq` can't parse it, OR a referenced reference-layer file vibe-kit was supposed to have created is missing (e.g., `gstack-learnings.md` doesn't exist despite the retrofit having claimed tier 2+), OR the briefing template substitution emits literal `{{slot}}` placeholders — invoke `/vibe-bug` via the Skill tool. NOT a trigger: gstack reference dir empty (user might not have gstack history yet), Taskmaster absent (tier 2 retrofit doesn't install it). See `skill/vibe-bug/SKILL.md` for the full trigger rubric.
