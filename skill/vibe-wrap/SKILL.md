---
name: vibe-wrap
description: End-of-session lifecycle for vibe-kit-retrofitted repos. Invokes /retro, marks completed Taskmaster tasks, syncs gbrain (if registered), writes a handoff stub to ~/.vibe-kit/projects/<key>/handoffs/ that /context-restore will pick up, and prompts for KNOWN_GOTCHAS additions. Use when the user says "wrap up", "end of session", "/vibe-wrap", "wrap this session", "close out", "I'm done for the day", or when the session has clearly reached a natural stopping point.
---

# /vibe-wrap — end-of-session lifecycle for vibe-kit repos

**The point:** sessions end and stuff falls through the cracks. Tasks don't get marked done, learnings don't get logged, gbrain falls out of sync, the next session has no handoff to pick up from. This skill catches all five in 3-5 minutes.

**Hard requirement:** the cwd must be a vibe-kit-retrofitted repo (has `.vibe-kit-version`). If not, tell the user to run `/vibe-retrofit` first and stop.

## Phase 0 — Confirm wrap

Briefly summarize what the session worked on (1-2 lines from your own context — what files changed, what got shipped, what was the main thread). Then:

> "Ready to wrap up the session? I'll run /retro, surface any Taskmaster tasks that look done, sync gbrain (if set up), write a handoff stub for next session, and ask about new KNOWN_GOTCHAS. ~3-5 min."

Options:
- **Wrap up now** (Recommended)
- **Skip /retro** (run the rest)
- **Just handoff + KNOWN_GOTCHAS** (minimal)
- **Cancel**

If user picks Cancel, report stopped + exit.

## Phase 1 — /retro (unless skipped)

Invoke the gstack `/retro` skill via the Skill tool. It does the heavy lifting (commit history analysis, what shipped, mistakes-made-twice prompts, stats). The output lands in the user's gstack-managed retro location, which the vibe-kit hook briefing already surfaces on next session start.

If `/retro` produces a summary worth reusing in the handoff, capture the key lines for Phase 4.

## Phase 2 — Taskmaster reconciliation (skip if no `.taskmaster/`)

If the cwd has `.taskmaster/`, run:

```bash
echo "=== In-progress ==="
task-master list --status=in-progress 2>/dev/null | head -20
echo ""
echo "=== Pending (top 5) ==="
task-master list --status=pending 2>/dev/null | head -10
```

Show the user the in-progress + top-5 pending. Ask via AskUserQuestion:

> "Any of these actually done now? (You can tell me task IDs to mark done, or 'none'.)"

For each ID the user gives:

```bash
task-master set-status <id> done
```

Show the user the new pending count for context.

**If the user mentioned new work in this session that isn't in Taskmaster:** propose adding it.

```bash
# Only with explicit user confirmation per task:
task-master add-task --prompt "<description>" 2>/dev/null
```

Don't auto-add — ask first. Anything you'd mark `add-task` should be a real, scoped piece of work the user agrees should be tracked.

## Phase 3 — gbrain sync (skip if gbrain not set up for this repo)

Check if gbrain is installed AND this repo is a registered source:

```bash
gbrain_active=0
if command -v gbrain >/dev/null 2>&1; then
  # Check if cwd matches any source's local_path
  if gbrain sources list 2>/dev/null | grep -F "$(pwd)" >/dev/null 2>&1; then
    gbrain_active=1
  fi
fi
echo "gbrain_active=$gbrain_active"
```

If `gbrain_active=1`, ask the user:

> "Sync gbrain for this repo? It'll re-index any markdown changes from this session. ~30s-2min depending on diff size."

Options:
- **Sync now** (Recommended)
- **Skip**

If user confirms:

```bash
# Find the source slug for this repo
source_slug=$(gbrain sources list 2>/dev/null | grep -B1 -F "$(pwd)" | head -1 | awk '{print $1}')
gbrain sync --source "$source_slug" 2>&1 | tail -20
```

If gbrain isn't installed OR the cwd isn't a registered source, skip this phase silently. Mention in the final report that gbrain wasn't synced (with one-line reason).

## Phase 4 — Handoff stub

Always run this phase. The handoff is the single highest-value artifact this skill produces — it's what `/context-restore` picks up next session.

Read `.vibe-kit-version` to get the project_key:

```bash
project_key=$(jq -r '.project_key // ""' .vibe-kit-version)
[ -z "$project_key" ] && project_key=$(basename "$(pwd)")
handoff_dir="$HOME/.vibe-kit/projects/$project_key/handoffs"
mkdir -p "$handoff_dir"
handoff_file="$handoff_dir/handoff-$(date +%Y%m%d-%H%M%S).md"
echo "$handoff_file"
```

Draft the handoff content from YOUR SESSION CONTEXT. Don't ask the user to fill in a template — synthesize from what you remember. Sections:

```markdown
# Handoff — <YYYY-MM-DD HH:MM>

## Session summary
<1-3 lines on what this session worked on>

## What shipped
<bullet list of concrete user-visible outcomes — features, fixes, releases tagged>

## What's in flight
<what was being worked on but not finished. Reference branches, PRs, file paths.>

## Decisions made (worth carrying forward)
<architectural calls, scope choices, anything future-you might second-guess. Quote any user direction verbatim.>

## Next steps
<concrete first move for the next session. Should be specific enough that future-you can start in <5 minutes.>

## Open questions
<anything you didn't get answered. Things the next session should ask the user about early.>

## Context to load
<list any files / commits / PRs / docs that next-session-you would need to read first>
```

Show the user the draft. Ask:

> "Handoff draft above. Approve as-is, edit any section, or skip the handoff entirely?"

On approve: Write the file to `$handoff_file`. Mention the path in the final report.
On edit: take the user's edits, iterate until approved, then write.
On skip: don't write. Note in final report.

## Phase 5 — KNOWN_GOTCHAS prompt

Ask:

> "Anything bite you this session worth adding to KNOWN_GOTCHAS.md? (Subtle bugs, surprising behavior, config that took 30+ min to find — things future-you should know without re-discovering.)"

If yes, ask for the entry. Format:

```markdown
## <YYYY-MM-DD>: <short title>

**Symptom:** <what you saw>

**Cause:** <what was actually going on>

**Fix:** <how to handle it>

**Detection:** <how to spot it next time>
```

Append to `KNOWN_GOTCHAS.md` at repo root (create if missing — minimal scaffold). One entry per real gotcha. Don't pad with weak ones.

## Phase 6 — Final report

Tell the user:

```
✓ Wrap complete.
  • /retro: <run | skipped>
  • Taskmaster: marked N done, M still in-progress, K pending
  • gbrain sync: <ran | skipped reason>
  • Handoff: ~/.vibe-kit/projects/<key>/handoffs/handoff-<ts>.md
  • KNOWN_GOTCHAS: <added 1 entry | nothing to add>

Next session opens with the briefing from ~/.vibe-kit/projects/<key>/reference/
and will pick up the handoff above. /context-restore surfaces it explicitly.
```

## Edge cases

- **No `.taskmaster/`** → skip Phase 2 cleanly. Note in final report.
- **gbrain installed but cwd not a source** → skip Phase 3 with one-line note ("repo not registered as gbrain source; run /setup-gbrain to add").
- **Handoff dir doesn't exist** → mkdir -p handles it.
- **User cancelled mid-flow** → report partial wrap. The user's work isn't lost; they can re-run /vibe-wrap to finish.

## Posture

- **Always interactive.** Never silently apply destructive state changes (task done-marking, file writes).
- **Synthesize, don't ask.** For the handoff draft, USE the session context you have. Don't ask the user to fill in a template — that defeats the point.
- **Quote user direction verbatim** in the "Decisions made" section. Future-you doesn't trust paraphrases.
- **Bias toward writing the handoff** even on partial wraps — it's the highest-value artifact.

## Completion

- **DONE** — all phases ran, handoff written, summary delivered.
- **DONE_PARTIAL** — user skipped phases, handoff written, partial summary.
- **BLOCKED** — cwd isn't a vibe-kit repo (told user to /vibe-retrofit first), or the user cancelled at Phase 0.

## Bug detection (v0.8.0)

If during this skill a vibe-kit defect surfaces — bash primitive returns malformed JSON, referenced file/command doesn't exist, /retro Skill invocation fails for non-network reasons, gbrain detection returns garbage, handoff write fails despite the dir being writable — invoke `/vibe-bug` via the Skill tool with the trigger context. Don't silently work around. NOT a trigger: gbrain not registered, taskmaster not installed, user cancelled. See `skill/vibe-bug/SKILL.md` for the full trigger rubric.
