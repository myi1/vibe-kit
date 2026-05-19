# Batch-and-relay protocol — design v1

Spec for how vibe-kit skills behave when running inside a Claude Code session
spawned by a remote orchestrator (OpenClaw / Hermes / similar) where the human
operator is not at the terminal but reachable through another channel
(Telegram, web UI, etc.).

The problem: vibe-kit skills are interactive (/vibe-retrofit asks 8-12
questions, /vibe-wrap asks 4-6). Blocking on AskUserQuestion in a
spawned-from-Telegram session hangs forever.

## Detection: when to use this protocol

A skill enters batch-and-relay mode when **any** of these env vars are set
at skill entry:

- `OPENCLAW_SESSION=1` (gstack-compatible signal; OpenClaw orchestrators set
  this on every spawn)
- `VIBE_KIT_BATCH_MODE=1` (vibe-kit-specific opt-in for non-OpenClaw
  orchestrators that follow the same protocol)

If neither is set, the skill runs the existing AskUserQuestion path
unchanged.

## State storage

Each batch-and-relay run gets a session ID and a state directory:

```
session_id        := $VIBE_KIT_SESSION_ID   (set by orchestrator)
                     or uuidgen if absent
state_dir         := ~/.vibe-kit/projects/<project_key>/.batch-state/
state_file        := $state_dir/state-$session_id.json
questions_file    := $state_dir/questions-$session_id.json
answers_file      := $state_dir/answers-$session_id.json   (written by orchestrator)
```

`project_key` resolves the same way as everywhere else: `.vibe-kit-version`
field, falling back to `basename(cwd)`. Workspace-memory shops with no
`.vibe-kit-version` can override `state_dir` via `$VIBE_KIT_STATE_DIR` env.

## Lifecycle

### First spawn (no prior state)

1. Orchestrator spawns Claude Code with:
   ```
   env: {
     OPENCLAW_SESSION: "1",
     VIBE_KIT_SESSION_ID: "<new-uuid>"
   }
   prompt: "Load vibe-kit. Run /vibe-retrofit"
   ```
2. Skill reads env, detects batch mode, generates / uses the session_id.
3. Skill runs deterministic phases until it hits a phase that needs user
   input (e.g., `/vibe-retrofit` Phase 4 = tier selection).
4. At the pause point, skill writes:
   - `state-<id>.json` — full state needed to resume (current phase,
     completed phases, in-flight data like tier choice / drafted files)
   - `questions-<id>.json` — the questions to ask
5. Skill emits a single line to stdout:
   ```
   [VIBE-KIT:BATCH-PAUSE] <abs-path-to-questions-file>
   ```
6. Skill exits 0.

### Orchestrator turn

1. Orchestrator's spawned-session output watcher catches the
   `[VIBE-KIT:BATCH-PAUSE]` sentinel.
2. Orchestrator reads the questions file (JSON, schema below).
3. Orchestrator renders to the user surface (Telegram message with
   inline buttons, web form, etc.).
4. User answers.
5. Orchestrator writes the answers to `answers-<id>.json` (schema below).
6. Orchestrator re-spawns Claude Code with:
   ```
   env: {
     OPENCLAW_SESSION: "1",
     VIBE_KIT_SESSION_ID: "<same-uuid>",
     VIBE_KIT_BATCH_ANSWERS: "<abs-path-to-answers-file>"
   }
   prompt: "Resume vibe-kit session <uuid>"
   ```

### Resume spawn (with answers)

1. Skill reads `VIBE_KIT_BATCH_ANSWERS` env, loads answers.
2. Skill reads `state-<id>.json` to know where it left off.
3. Skill applies answers to the in-flight phase.
4. Skill continues normal flow until next pause OR completion.
5. On completion, skill emits:
   ```
   [VIBE-KIT:BATCH-COMPLETE] <abs-path-to-final-report-file>
   ```
   and exits 0.

### Cancellation

If the user cancels in the orchestrator UI:

1. Orchestrator writes `answers-<id>.json` with `{"cancelled": true}`.
2. Re-spawns as above.
3. Skill reads, sees cancelled, runs cleanup phase (e.g., for
   /vibe-retrofit, leaves the partial scaffold drafts in place but
   doesn't commit), writes:
   ```
   [VIBE-KIT:BATCH-CANCELLED]
   ```
4. Cleans up state files. Exits 0.

## Schemas

### `questions-<id>.json`

```json
{
  "schema_version": 1,
  "session_id": "<uuid>",
  "skill": "vibe-retrofit",
  "phase": "tier_selection",
  "questions": [
    {
      "id": "tier_choice",
      "header": "Tier choice",
      "question": "Which retrofit tier? Tier 1 = CLAUDE.md only...",
      "options": [
        {
          "label": "Tier 3 (Recommended)",
          "description": "Full retrofit including Taskmaster + curated PRD",
          "recommended": true,
          "value": "3"
        },
        {"label": "Tier 2", "description": "...", "value": "2"},
        {"label": "Tier 1", "description": "...", "value": "1"}
      ],
      "multi_select": false,
      "allow_other": false
    }
  ],
  "created_at": "2026-05-19T20:00:00Z"
}
```

The question shape mirrors `AskUserQuestion`'s payload so the orchestrator
can render with the same affordances (buttons, multi-select checkboxes, free-
text fallback).

### `answers-<id>.json`

```json
{
  "schema_version": 1,
  "session_id": "<uuid>",
  "cancelled": false,
  "answers": [
    {
      "id": "tier_choice",
      "selected_value": "3",
      "selected_label": "Tier 3 (Recommended)",
      "other_text": null
    }
  ],
  "answered_at": "2026-05-19T20:01:30Z"
}
```

For multi-select questions, `selected_value` becomes an array.

### `state-<id>.json`

Skill-defined opaque blob. Vibe-kit's reference skills use:

```json
{
  "schema_version": 1,
  "session_id": "<uuid>",
  "skill": "vibe-retrofit",
  "current_phase": "tier_selection",
  "completed_phases": ["preflight", "discovery", "discovery_review"],
  "phase_data": {
    "discovery_review": {
      "missed_dirs": ["apps/foo/docs/bar/"]
    }
  },
  "created_at": "2026-05-19T19:55:00Z",
  "updated_at": "2026-05-19T20:00:00Z"
}
```

Each skill documents its phase enum + `phase_data` shape in the SKILL.md
under a "## Batch-and-relay state" section.

## Sentinels (stdout, single line, anchored)

The orchestrator MUST detect these via line-anchored grep (^/$ anchors) to
avoid false positives in prose output:

| Sentinel | Meaning | Trailing data |
|---|---|---|
| `[VIBE-KIT:BATCH-PAUSE] <path>` | Need user input. Read questions file at `<path>`. | absolute path |
| `[VIBE-KIT:BATCH-COMPLETE] <path>` | Skill finished cleanly. Final report at `<path>`. | absolute path |
| `[VIBE-KIT:BATCH-CANCELLED]` | Skill cleaned up after user cancel. | (none) |
| `[VIBE-KIT:BATCH-ERROR] <message>` | Unrecoverable failure. Skill exited with diagnostic. | free-form text |

## State cleanup

- On `BATCH-COMPLETE` or `BATCH-CANCELLED`, the skill removes its
  `state-<id>.json` and `questions-<id>.json` files.
- The orchestrator removes `answers-<id>.json` after re-spawn.
- A background sweep removes stale state files older than 24h (handled by
  `vibe-retrofit doctor --sweep-batch-state` — future).

## What this is NOT

- **Not** a generic agent-spawning protocol. Vibe-kit-specific.
- **Not** opinionated about which orchestrator implements it. OpenClaw,
  Hermes, a custom Telegram bot — all fine.
- **Not** an alternative to AskUserQuestion in interactive sessions. Falls
  through to AskUserQuestion when env not set.
- **Not** a place to add new question types beyond what AskUserQuestion
  already supports. The question schema is a strict subset.

## Why file-based + stdout sentinels (vs. pure stdout JSON)

Three reasons:

1. **stdout pollution.** Skills produce lots of stdout for the user
   (status, draft previews, summaries). Embedding JSON inline + parsing
   requires fragile sentinel-pair boundaries (`[BEGIN-JSON] ... [END-JSON]`).
   File-based avoids this entirely.

2. **Question size.** Some questions (especially scaffold drafts where
   the "options" include multi-paragraph prose previews) can exceed
   stdout-line buffer limits. Files handle arbitrary size.

3. **Idempotency.** If the orchestrator misses the sentinel and the
   spawn ends, the questions file still exists on disk for recovery.

## Open questions (defer to v0.7.2+)

- **Streaming answers.** Currently the skill pauses + re-spawns per
  question batch. Could questions stream over a single long-lived
  session? Probably not worth it — re-spawn cost is low (~1s).
- **Multi-skill interleaving.** If /vibe-wrap pauses, can /vibe-retrofit
  also pause in parallel? Today: no, session_id is per-skill-run.
  Future: not needed for normal use.
- **Failure recovery.** If the orchestrator never returns answers, the
  skill state file dangles. The 24h sweep covers it. No active
  re-prompting from skill side.
