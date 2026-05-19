# Pattern 2 — Session-wrap ritual (methodology guide)

vibe-kit's reference impl (`skill/vibe-wrap/SKILL.md`) is a Claude Code skill
written in markdown the model reads as instructions. It's LLM-platform-
specific. This guide extracts the **methodology** so you can adapt it to
any agent stack — Claude Code, OpenClaw spawning Claude Code, a Python
script with a different LLM, or a manual checklist.

See [`../../docs/PATTERNS.md#pattern-2`](../../docs/PATTERNS.md) for the
problem statement.

## The 6-phase ritual

Each phase is one user-facing question or action. Don't add phases; six is
the floor for "catches the work that falls through" and the ceiling for
"~3-5 min and you're done."

### Phase 1 — Confirm wrap

**Why:** sometimes the user invokes /vibe-wrap by mistake, or hasn't
actually stopped working. The cheapest possible check.

**Shape:** show a 1-2 line summary of what the session did (synthesized
from agent context — what files changed, what was the main thread).
Ask "ready to wrap?" with options:
- Wrap fully (Recommended)
- Skip retrospective (faster)
- Minimal — just handoff + gotchas
- Cancel

**Cancel must be an option.** The skill must be safe to bail out of.

### Phase 2 — Retrospective

**Why:** end-of-session is when you can name what shipped and what
went sideways. Logged retros compound into a quarterly review.

**Shape:** Invoke an existing /retro skill if available (Claude Code +
gstack ship one). If not, ask the user:
- What shipped (1-3 bullets, concrete user-visible outcomes)
- What surprised you
- Mistakes you made twice (these graduate to Pattern 5 KNOWN_GOTCHAS
  if recurring)
- Workflow tweaks for next session

Write to wherever retros land in your stack. vibe-kit + gstack write to
markdown; JP-style setups append to `memory/daily/YYYY-MM-DD.md` or a
dedicated `memory/retros/`.

### Phase 3 — Task reconciliation

**Why:** "in-progress" tasks rot. Without this phase, your task tracker
becomes graveyard within a month.

**Shape:** show the user:
- All in-progress tasks (full list — they're claiming time)
- Top 5-10 pending tasks (the next-up surface)

Ask: which of these are actually done now? Mark them.

Then: did this session uncover NEW work not in the tracker? Per-task
confirmation before adding. Don't auto-add — the user should opt in to
each.

**Integration points:** Taskmaster (vibe-kit), `memory/commitments.jsonl`
(JP-style), GitHub Issues, Linear, whatever. Same phase, different I/O.

### Phase 4 — Memory sync (search backend)

**Why:** if you have a vector index over your project's markdown / code,
end-of-session is the obvious moment to incrementally update it. Next
session's search returns this session's work.

**Shape:** detect if a search backend is registered for this project. If
yes:
- Ask "sync now? (default: yes if markdown changed)"
- Run the sync, surface result count

If no backend, skip this phase silently.

**Integration points:** gbrain (vibe-kit reference), custom indexers
(JP-style memmap+numpy), commercial (Qdrant, Weaviate), agent-platform-
native (Cursor's index, Cody's). Same phase, different I/O.

### Phase 5 — Handoff write

**The highest-value artifact.** This is what the next session reads to
load context.

**Shape:** synthesize from session context — DON'T ask the user to fill
in a blank template (that's the anti-pattern most retro tools fall into).

Sections:
- **Session summary** (1-3 lines)
- **What shipped** (concrete user-visible outcomes — features, fixes,
  releases tagged)
- **What's in flight** (active branches, PRs, file paths)
- **Decisions made (worth carrying forward)** — quote user direction
  VERBATIM. Future-you doesn't trust paraphrases.
- **Next steps** (specific enough that future-you can start in <5 min)
- **Open questions** (anything you didn't answer)
- **Context to load** (files / commits / docs the next session should
  read first)

Show the draft. User approves / edits / skips. On approve, write.

**Where to write:** location your next session's start ritual will
surface.
- vibe-kit: `~/.vibe-kit/projects/<key>/handoffs/handoff-<timestamp>.md`
- JP-style: `workspace/memory/sessions/<peer>/<id>-<date>.md` (markdown
  prose) + append a row to `workspace/memory/decisions.jsonl` for the
  structured deltas
- Custom: anywhere the next session's loader checks

### Phase 6 — KNOWN_GOTCHAS prompt

**Why:** subtle bugs you spent 30 min finding should not bite future-you
again. The retro might mention it; the gotcha file is the lookup table.

**Shape:** ask "anything bite you this session worth recording for
future-you?" If yes, ask for the entry. Format:

```markdown
## <YYYY-MM-DD>: <short title>

**Symptom:** <what you saw>
**Cause:** <what was actually going on>
**Fix:** <how to handle it>
**Detection:** <how to spot it next time>
```

Append to KNOWN_GOTCHAS.md at repo root (or your project's equivalent).
One entry per real gotcha. Don't pad with weak ones — that destroys
signal.

## Load-bearing decisions

If you only adopt three:

1. **Phase 5 (handoff) is non-negotiable.** Skip 2/3/4/6 if you must,
   but always write the handoff. It's the bookend that makes Pattern 5
   of the session-start ritual work.
2. **Phase 5 SYNTHESIZES, doesn't ask.** A blank template is friction
   the user skips. Draft from session context, show for approval.
3. **Phase 3 (task reconciliation) is interactive.** Don't auto-mark
   done. The user is the only one who knows. Same for adding new tasks.

## Integration notes by stack

| Stack | Handoff location | Task surface | Retro surface |
|---|---|---|---|
| Claude Code + vibe-kit | `~/.vibe-kit/projects/<key>/handoffs/` | Taskmaster | gstack /retro |
| Claude Code + gstack alone | `~/.gstack/projects/<...>/handoffs/` | Taskmaster or none | gstack /retro |
| OpenClaw + JP-style memory | `workspace/memory/sessions/<peer>/` + JSONL | `commitments.jsonl` | `memory/retros/` |
| Cursor + manual | `.notes/handoffs/` in repo | TODOs in code | manual journal |
| Generic LLM script | wherever | wherever | wherever |

The pattern is the same. The I/O changes.

## What's NOT included

- **Commits.** /vibe-wrap is end-of-session, not end-of-feature. Don't
  auto-commit. The handoff records what's uncommitted.
- **Push / PR.** Same — /vibe-wrap is reflection, not deployment.
  Separate skill for that (vibe-kit doesn't have one; gstack has
  /ship + /land-and-deploy).
- **Time tracking.** Out of scope. The daily-line in Pattern 5
  captures it cheaply if you want.
