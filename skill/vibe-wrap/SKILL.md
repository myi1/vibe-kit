---
name: vibe-wrap
description: End-of-session lifecycle for vibe-kit-retrofitted repos. Invokes /retro, marks completed tasks (Taskmaster or JP-style commitments.jsonl based on memory_format), syncs gbrain (if registered), writes a handoff stub for the next session, and prompts for KNOWN_GOTCHAS additions. Supports two output modes per `vibe-retrofit memory-format`: default `vibe-kit-markdown` (per-repo) and `jp-jsonl` (workspace-wide markdown + JSONL deltas). Use when the user says "wrap up", "end of session", "/vibe-wrap", "wrap this session", "close out", "I'm done for the day", or when the session has clearly reached a natural stopping point.
---

# /vibe-wrap — end-of-session lifecycle for vibe-kit repos

**The point:** sessions end and stuff falls through the cracks. Tasks don't get marked done, learnings don't get logged, gbrain falls out of sync, the next session has no handoff to pick up from. This skill catches all five in 3-5 minutes.

**Hard requirement:** the cwd must be a vibe-kit-retrofitted repo (has `.vibe-kit-version`). If not, tell the user to run `/vibe-retrofit` first and stop.

## Phase 0 — Mode detection + confirm wrap

Detect memory_format FIRST. It changes Phase 2 (task reconciliation), Phase 4 (handoff write), and triggers a peer prompt for jp-jsonl.

```bash
# Resolve memory_format (env > global config > per-repo > default)
mode=$(vibe-retrofit memory-format status 2>/dev/null | head -1 | awk '{print $2}')
[ -z "$mode" ] && mode="vibe-kit-markdown"
echo "memory_format: $mode"

# For jp-jsonl mode, also read memory_dir + operator_name from ~/.vibe-kit/config.json
if [ "$mode" = "jp-jsonl" ]; then
  memory_dir=$(jq -r '.memory_dir' ~/.vibe-kit/config.json)
  operator_name=$(jq -r '.operator_name' ~/.vibe-kit/config.json)
  confidential_paths=$(jq -r '.confidential_paths // [] | join(" ")' ~/.vibe-kit/config.json)
  echo "  memory_dir: $memory_dir"
  echo "  operator_name: $operator_name"
fi

```

Then briefly summarize what the session worked on (1-2 lines from your own context — what files changed, what got shipped, what was the main thread). Then:

> "Ready to wrap up the session? I'll run /retro, surface any pending tasks that look done, sync gbrain (if set up), write a handoff stub for next session, and ask about new KNOWN_GOTCHAS. ~3-5 min. (Memory format: <mode>.)"

Options:
- **Wrap up now** (Recommended)
- **Skip /retro** (run the rest)
- **Just handoff + KNOWN_GOTCHAS** (minimal)
- **Cancel**

If user picks Cancel, report stopped + exit.

### Phase 0.5 — Peer prompt (jp-jsonl only)

When `mode = jp-jsonl`, ask the user who this session was with/for. The peer drives the handoff filepath (`<memory_dir>/sessions/<peer>/...`) and gets written into every JSONL row.

```bash
# Surface peer candidates from memory/people/
candidates=$(ls "$memory_dir/people/" 2>/dev/null | sed 's/\.md$//' | head -10)
echo "Known peers: $candidates"
```

Show the candidates + ask via AskUserQuestion:

> "Who is this session with/for? (Free text accepted — pick from list or type a new name.)"

Options: top 3-4 candidates from the people/ dir + "(other — I'll type it)" + "(none — leave peer null)".

If user picks "other", ask for the peer name as free text. If "none", set `peer: null` (still write the markdown to `<memory_dir>/sessions/_unassigned/`).

Store `peer` for Phase 4. Validate the chosen peer name doesn't contain `/` or `..` (filesystem safety).

## Phase 1 — /retro (unless skipped)

Invoke the gstack `/retro` skill via the Skill tool. It does the heavy lifting (commit history analysis, what shipped, mistakes-made-twice prompts, stats). The output lands in the user's gstack-managed retro location, which the vibe-kit hook briefing already surfaces on next session start.

If `/retro` produces a summary worth reusing in the handoff, capture the key lines for Phase 4.

## Phase 2 — Task reconciliation (mode-aware)

The task surface depends on `mode` and what's available in the workspace.

### Phase 2a — Taskmaster (when `.taskmaster/` exists)

Used in BOTH modes when Taskmaster is initialized — it's a real task tracker regardless of memory_format.

```bash
echo "=== In-progress ==="
task-master list --status=in-progress 2>/dev/null | head -20
echo ""
echo "=== Pending (top 5) ==="
task-master list --status=pending 2>/dev/null | head -10
```

Show the user the in-progress + top-5 pending. Ask via AskUserQuestion:

> "Any of these actually done now? (Tell me task IDs to mark done, or 'none'.)"

For each ID the user gives:

```bash
task-master set-status <id> done
```

**If the user mentioned new work in this session that isn't in Taskmaster:** propose adding it (per-task confirmation, no auto-add).

### Phase 2b — JP-style commitments.jsonl (jp-jsonl mode, no `.taskmaster/`)

When `mode = jp-jsonl` AND there's no `.taskmaster/`, read open commitments from JP's append-only log:

```bash
commitments_file="$memory_dir/commitments.jsonl"
if [ -f "$commitments_file" ]; then
  # Show open commitments (most recent status per `what` field wins)
  jq -c 'select(.status == "open")' "$commitments_file" | tail -20
fi
```

Show the user the same UI as Phase 2a:

> "Any of these commitments now done? (Tell me which `what` strings, or 'none'.)"

**Append-only rule** (JP's discipline): mark done by appending a NEW line with `status: "done"`, NEVER edit the existing row. The most recent line per `what` wins on read.

For each commitment the user marks done:

```bash
# Append-only status flip
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
original=$(jq -c --arg w "$WHAT" 'select(.status=="open" and .what==$w)' "$commitments_file" | tail -1)
echo "$original" | jq --arg ts "$ts" --arg by "$operator_name" \
  '. + {ts: $ts, status: "done", closed_by: $by, source: "vibe-kit"}' \
  >> "$commitments_file"
```

If user mentioned new commitments uncovered this session, also append (with confirmation):

```bash
echo '{"ts":"'$ts'","to":"'$peer'","what":"<...>","due":"<ISO date or null>","status":"open","source":"vibe-kit","by":"'$operator_name'"}' \
  >> "$commitments_file"
```

### Phase 2c — Neither available

When mode = vibe-kit-markdown AND no .taskmaster, OR mode = jp-jsonl AND no commitments.jsonl: skip this phase cleanly. Note in final report.

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

## Phase 4 — Handoff (mode-aware)

Always run this phase. The handoff is the single highest-value artifact this skill produces — it's what the next session picks up.

### Auto-confidential detection (both modes, run first)

Before drafting, decide if this session should be marked confidential. Scan the file scope:

```bash
session_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s-$$)
files_changed=$(git diff --name-only HEAD 2>/dev/null; git status --short 2>/dev/null | awk '{print $2}')
confidential=false
# Match against configured paths (jp-jsonl) or built-in defaults
if [ "$mode" = "jp-jsonl" ]; then
  paths="$confidential_paths"
else
  paths="credentials/ vault/ .env .key .pem .confidential/"
fi
for p in $paths; do
  if echo "$files_changed" | grep -qE "(^|/)$p"; then
    confidential=true
    break
  fi
done
echo "session_id: $session_id"
echo "confidential: $confidential"
```

### Phase 4a — vibe-kit-markdown mode (default)

```bash
project_key=$(jq -r '.project_key // ""' .vibe-kit-version)
[ -z "$project_key" ] && project_key=$(basename "$(pwd)")
handoff_dir="$HOME/.vibe-kit/projects/$project_key/handoffs"
mkdir -p "$handoff_dir"
handoff_file="$handoff_dir/handoff-$(date +%Y%m%d-%H%M%S).md"
```

Draft the markdown handoff from session context (see "Handoff prose template" below). Show user, get approval, write to `$handoff_file`. Include frontmatter:

```yaml
---
session_id: <uuid>
ts: <ISO timestamp>
confidential: <true|false>
---
```

### Phase 4b — jp-jsonl mode

Write to TWO surfaces atomically:

**(1) Markdown prose** to `<memory_dir>/sessions/<peer>/<session-id>-<date>.md`:

```bash
peer_dir="${peer:-_unassigned}"
session_dir="$memory_dir/sessions/$peer_dir"
mkdir -p "$session_dir"
session_md="$session_dir/$session_id-$(date +%Y-%m-%d).md"
```

Draft using same prose template. Include same frontmatter (session_id, ts, confidential, peer, repo).

**(2) Structured JSONL deltas** appended to `<memory_dir>/{decisions,commitments,follow-ups}.jsonl`. Build each row from the relevant section of the handoff draft:

```bash
# For each line in "Decisions made (worth carrying forward)" section:
echo '{"ts":"'$ts'","decision":"<text>","by":"'$operator_name'","scope":"single","source":"vibe-kit","session_id":"'$session_id'","peer":"'$peer'","repo":"'$repo_basename'","confidential":'$confidential'}' \
  >> "$memory_dir/decisions.jsonl"

# For each "Next steps" item with a deadline:
echo '{"ts":"'$ts'","to":"'$peer'","what":"<text>","due":"<ISO>","status":"open","source":"vibe-kit","session_id":"'$session_id'","confidential":'$confidential'}' \
  >> "$memory_dir/commitments.jsonl"

# For each "Open questions" item waiting on someone:
echo '{"ts":"'$ts'","what":"<text>","with":"<who>","due":null,"status":"open","source":"vibe-kit","session_id":"'$session_id'","confidential":'$confidential'}' \
  >> "$memory_dir/follow-ups.jsonl"
```

**Crucial:** validate each row is valid JSON before append. Use `jq -e '.' <<< "$row"` — if it fails, save to local error log and tell user (don't corrupt the user's append-only file with broken JSON).

### Phase 4c — Daily-line summary (both modes)

Append one line to the daily journal:

```bash
if [ "$mode" = "jp-jsonl" ]; then
  daily_file="$memory_dir/$(date +%Y-%m-%d).md"
else
  daily_file="$HOME/.vibe-kit/projects/$project_key/daily/$(date +%Y-%m-%d).md"
  mkdir -p "$(dirname "$daily_file")"
fi
# Create daily file with minimal header if missing
[ -f "$daily_file" ] || echo "# Daily journal — $(date +%Y-%m-%d)" > "$daily_file"
# Append one-line summary
start=$(date -u +%H:%M -r ~/.claude/sessions/.. 2>/dev/null || echo "??:??")
end=$(date +%H:%M)
echo "- $start-$end ${repo_basename}: <one-line summary from session context>. (handoff: $session_md)" >> "$daily_file"
```

### Handoff prose template (used by both 4a and 4b)

Draft from YOUR SESSION CONTEXT. Don't ask the user to fill in a blank — synthesize from what you remember. Sections:

```markdown
---
session_id: <uuid>
ts: <ISO>
confidential: <bool>
peer: <name|null>
repo: <basename|null>
---

# Handoff — <YYYY-MM-DD HH:MM>

## Session summary
<1-3 lines on what this session worked on>

## What shipped
<bullet list of concrete user-visible outcomes — features, fixes, releases tagged>

## What's in flight
<what was being worked on but not finished. Reference branches, PRs, file paths.>

## Decisions made (worth carrying forward)
<architectural calls, scope choices, anything future-you might second-guess. Quote any user direction verbatim. EACH BULLET becomes a row in decisions.jsonl when mode=jp-jsonl.>

## Next steps
<concrete first move for the next session. Specific enough that future-you can start in <5 min. ITEMS WITH A DEADLINE become commitments.jsonl rows when mode=jp-jsonl.>

## Open questions
<anything you didn't get answered. ITEMS WAITING ON SOMEONE become follow-ups.jsonl rows when mode=jp-jsonl.>

## Context to load
<list any files / commits / PRs / docs that next-session-you would need to read first>
```

Show the user the draft. Ask:

> "Handoff draft above. Approve as-is, edit any section, or skip the handoff entirely?"

On approve: write markdown + (if jp-jsonl) append JSONL rows + append daily-line. Tell user paths in final report.
On edit: take the user's edits, iterate until approved, then write.
On skip: don't write anything. Note in final report.

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

Tell the user a mode-appropriate summary:

**vibe-kit-markdown mode:**
```
✓ Wrap complete (memory_format: vibe-kit-markdown).
  • /retro: <run | skipped>
  • Taskmaster: marked N done, M in-progress, K pending
  • gbrain sync: <ran | skipped reason>
  • Handoff: ~/.vibe-kit/projects/<key>/handoffs/handoff-<ts>.md
  • Daily line: ~/.vibe-kit/projects/<key>/daily/<date>.md
  • KNOWN_GOTCHAS: <added 1 entry | nothing to add>
  • Confidential: <true|false>

Next session opens with the briefing from ~/.vibe-kit/projects/<key>/reference/.
```

**jp-jsonl mode:**
```
✓ Wrap complete (memory_format: jp-jsonl, peer: <name>).
  • /retro: <run | skipped>
  • Commitments: marked N done, K still open (appended rows to commitments.jsonl)
  • gbrain sync: <ran | skipped reason>
  • Markdown prose:    <memory_dir>/sessions/<peer>/<session-id>-<date>.md
  • decisions.jsonl:   +N rows
  • commitments.jsonl: +M rows
  • follow-ups.jsonl:  +K rows
  • Daily journal:     <memory_dir>/<date>.md (+1 line)
  • KNOWN_GOTCHAS: <added 1 entry | nothing to add>
  • Confidential: <true|false> (auto-detected from file scope)

JP's indexer will pick up the new rows + markdown on its next 15-min cron pass.
```

## Edge cases

- **No `.taskmaster/` AND no `commitments.jsonl`** → skip Phase 2 cleanly. Note in final report.
- **jp-jsonl mode but `memory_dir` doesn't exist** → ABORT before writing anything. Tell user to re-run `vibe-retrofit memory-format set jp-jsonl` and fix the path.
- **jp-jsonl mode but write to memory_dir fails (perms, disk full)** → ABORT. Don't leave the user with half-written state. Save the in-flight handoff to a local fallback under `~/.vibe-kit/bug-reports/wrap-failed-<ts>.json` and tell them.
- **JSONL row fails jq validation** → don't append the broken row. Log to `~/.vibe-kit/bug-reports/jsonl-validation-<ts>.json`. Tell user. (This is a vibe-kit bug — invoke /vibe-bug after wrap.)
- **gbrain installed but cwd not a source** → skip with one-line note ("repo not registered as gbrain source; run /setup-gbrain to add").
- **User cancelled mid-flow** → report partial wrap. Work isn't lost; they can re-run /vibe-wrap to finish.
- **No git repo (using vibe-kit on a non-git dir)** → files_changed detection skips, confidential defaults false unless overridden.

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
