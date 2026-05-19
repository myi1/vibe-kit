# vibe-kit patterns

vibe-kit is methodology. The bash CLI + skills + hooks in this repo are
one reference implementation for Claude Code. The patterns below are
**portable** — adopt them in whatever shape your agent stack uses.

If your stack is workspace-wide markdown + JSONL + a custom vector
indexer (like Mubbashir's, served by JP), don't install vibe-kit.
Port the patterns into your existing dirs.

If your stack is per-repo Claude Code with hooks (like Yahya's), use
the reference impl directly via `git clone + bash bin/install.sh`.

Either way, six patterns to know.

---

## Pattern 1 — Per-turn nudge (PostToolUse + UserPromptSubmit)

**Problem.** When agents edit files, downstream systems (tasktrackers,
vector indexes, daily logs) drift. The agent doesn't remember to
sync because syncing is invisible work — it doesn't help with the
task at hand.

**Solution shape.** A pair of hooks:

- A **silent file-change logger** fires after every Write/Edit/MultiEdit
  tool call. Appends the touched file path to a per-project log.
  Latency ~1ms. No agent-visible output.
- A **nudge injector** fires on every user prompt. Reads the log. If
  it has entries AND there are actionable hints (e.g. taskmaster has
  in-progress tasks, gbrain is registered + .md files changed), it
  injects a soft context line for the current turn:
  > "Files X/Y/Z changed since last turn. If you finished a task,
  >  mark it done. If markdown changed, gbrain sync."
  Then it truncates the log so the same change set isn't nudged twice.

**Why not a Stop hook.** Forces the agent to keep responding instead
of stopping. Wrong shape for soft nudges. The pair pattern keeps
nudges out-of-band — they land on the NEXT turn-start, agent decides
whether to act.

**Why not "sync after every turn."** A typical sync (e.g. gbrain
re-index) is 10-30s. 50 turns × 20s = 17 min/day of latency added.
Disqualifying. The nudge pattern is ~0ms latency added per turn;
real cost only when the agent acts on the nudge, which is the agent's
informed choice.

**Vibe-kit's reference impl:**
- [`hooks/vibe-kit-posttooluse.sh`](../hooks/vibe-kit-posttooluse.sh) — file-change logger
- [`hooks/vibe-kit-userpromptsubmit.sh`](../hooks/vibe-kit-userpromptsubmit.sh) — nudge injector
- [`patterns/per-turn-nudge/`](../patterns/per-turn-nudge/) — extracted, parameterized version

**Porting checklist:**
1. Pick where the change log lives. Vibe-kit uses
   `~/.vibe-kit/projects/<key>/.pending-syncs/changes.log`.
   Workspace-memory shops should use `workspace/.pending-syncs/changes.log`
   or similar.
2. Pick which agent tools should trigger logging. Vibe-kit uses
   `Write|Edit|MultiEdit|NotebookEdit`. Add `Bash` if you want to
   nudge after shell commands too (chattier).
3. Pick which downstream systems get hints. Vibe-kit checks
   Taskmaster and gbrain. Substitute for your equivalents.
4. Pick the disable mechanism. Vibe-kit uses 3 paths (env, global
   config, per-repo). One is enough.

---

## Pattern 2 — Session-bounded ritual (`/vibe-wrap`)

**Problem.** Sessions end and stuff falls through the cracks. Tasks
stay "in-progress" forever. The vector index goes stale. The next
session has no handoff signal. You re-discover what you just figured
out.

**Solution shape.** A skill the user invokes at end-of-session that
sweeps six things:

1. **Confirm wrap.** 1-2 line summary of what the session worked on.
   Cheap signal so the user can cancel if they're not actually done.
2. **Retrospective.** Invoke the existing /retro skill via the Skill
   tool. Heavy lifting (commit history analysis, lessons logged) lives
   there. This skill just orchestrates.
3. **Task reconciliation.** Show in-progress + top-pending tasks.
   Ask which ones are actually done. Mark them. Offer to add NEW
   work surfaced this session.
4. **Memory sync.** If a vector index / search backend is registered
   for this repo, ask whether to sync now (default: yes if .md
   changed).
5. **Handoff write.** The high-value artifact. Synthesize from
   session context — don't ask the user to fill in a template (that
   defeats the point). Sections: summary, what shipped, what's
   in-flight, decisions made (quoted verbatim), next steps, open
   questions. Write to a location the next session's start ritual
   will surface.
6. **Known-gotchas prompt.** Anything bite you this session worth
   recording? Append structured entry to KNOWN_GOTCHAS or equivalent.

**Why interactive.** Synthesis works, but the user is the only one
who knows what's actually done vs. blocked vs. abandoned. Don't
auto-mark tasks done. Don't write the handoff without showing it
for approval.

**Why session-bounded.** Daily reflection (cron) catches most things
but loses the per-session "what specifically did I just do" detail.
The handoff stub captures that surgically.

**Vibe-kit's reference impl:**
- [`skill/vibe-wrap/SKILL.md`](../skill/vibe-wrap/SKILL.md) — the orchestrator
- Handoff dir: `~/.vibe-kit/projects/<project_key>/handoffs/handoff-<timestamp>.md`

**Porting checklist:**
1. Pick where handoffs land. Vibe-kit uses the global per-project dir.
   Workspace-memory shops should use `workspace/memory/sessions/<peer>/<id>-<date>.md`
   (JP's shape) or `workspace/memory/handoffs/<id>-<date>.md` (flat).
2. Pick the task-surface integration. Vibe-kit talks to Taskmaster.
   JP-style setups talk to `memory/commitments.jsonl`. Either path
   is read + write per the same phase.
3. Pick how the next session surfaces handoffs. Vibe-kit's SessionStart
   hook reads them. Workspace-memory shops can register them in
   `MEMORY.md` so the agent's normal recall includes them.

---

## Pattern 3 — Confidential-path autodetect

**Problem.** Handoff stubs leak secrets when sessions touched
`credentials/`, `.env*`, vault dirs, `.confidential/` (your-convention).
Asking the user "is this confidential?" on every handoff is friction
the user will skip or get wrong.

**Solution shape.** Look at the file paths in the session's scope.
If any match a known-secret pattern (configurable), set the handoff's
`confidential: true` automatically. Otherwise default `false`.

**Vibe-kit's reference impl:**
- v0.7.1 will land this in `/vibe-wrap`. Patterns: `.confidential/`,
  `credentials/`, `vault/`, `.env*`, `*.key`, `*.pem`. Configurable
  list per-project via `.vibe-kit-version.confidential_paths`.

**Porting checklist:**
1. Pick the confidential-path list. Defaults above are sane; add
   project-specific (e.g. `secrets/manifests/`).
2. Pick the consumer. Vibe-kit's handoffs are written to a single
   markdown file; the flag goes in frontmatter. JP-style JSONL
   shops use the `confidential: bool` field directly. Same
   detection logic, different write.

---

## Pattern 4 — Batch-and-relay for non-interactive contexts

**Problem.** Skills that ask 5-12 questions per run can't work when
the human operator is in Telegram and the agent is in a Claude Code
session spawned by an orchestrator. The questions hang forever.

**Solution shape.** Detect non-interactive context via env var.
Instead of blocking on the next AskUserQuestion, the skill:

1. Saves its current state to disk
2. Writes the pending questions to disk
3. Emits a single stdout sentinel line pointing at the questions file
4. Exits 0

The orchestrator catches the sentinel, renders questions on the user's
real surface (Telegram), collects answers, writes them to disk,
re-spawns the skill with answers attached.

The skill detects the answers env var, loads state, applies answers,
continues from the saved phase. Repeats until skill completes
(emits a `[VIBE-KIT:BATCH-COMPLETE]` sentinel) or user cancels
(`[VIBE-KIT:BATCH-CANCELLED]`).

**Vibe-kit's reference impl:**
- Full protocol spec at [`docs/design/batch-and-relay-protocol.md`](design/batch-and-relay-protocol.md)
- v0.7.1 will land it in /vibe-retrofit (highest-value first — most
  questions, most context-sensitive).
- /vibe-wrap will use auto-pick-recommended instead (cheaper,
  per JP's preference).
- /vibe-upgrade will skip the confirm gate entirely under
  $OPENCLAW_SESSION.

**Why per-skill, not blanket.** Skill-by-skill judgment. /vibe-retrofit
asks load-bearing questions (Mubbashir's call on TODO curation matters).
/vibe-wrap asks lower-stakes questions (recommended option is usually
right). Different defaults.

**Why file-based + stdout sentinels (vs. pure stdout JSON).** Skills
emit lots of prose stdout (status, draft previews). Inline JSON
requires fragile sentinel-pair parsing. Files handle arbitrary size
+ idempotency (orchestrator can read the file later if it missed
the sentinel live).

**Porting checklist:**
1. Adopt the env-var contract: `OPENCLAW_SESSION=1` is gstack-compatible;
   use that. Plus `VIBE_KIT_SESSION_ID` for per-run identity.
2. Pick state + questions + answers dir. Vibe-kit uses
   `~/.vibe-kit/projects/<key>/.batch-state/`. Override via
   `$VIBE_KIT_STATE_DIR`.
3. Adopt the 4 sentinel strings verbatim if you want
   orchestrator-portability across vibe-kit-aware tools:
   `[VIBE-KIT:BATCH-PAUSE]`, `[VIBE-KIT:BATCH-COMPLETE]`,
   `[VIBE-KIT:BATCH-CANCELLED]`, `[VIBE-KIT:BATCH-ERROR]`.

---

## Pattern 5 — Daily-line summary

**Problem.** Daily reflection covers the day's arc but loses
per-session granularity. Knowing "I worked on X between 14:00 and
16:30, shipped Y, blocked on Z" matters for the weekly retro.

**Solution shape.** /vibe-wrap (Pattern 2) appends one line to
`<daily-log-dir>/YYYY-MM-DD.md` per session-wrap. Format:

```
- 14:00-16:30 <repo>: <one-line summary>. (handoff: <path>)
```

If the daily log doesn't exist, create it with a minimal header.
If it does, append.

**Vibe-kit's reference impl:**
- v0.7.1 will land this in /vibe-wrap.
- Defaults to `~/.vibe-kit/projects/<key>/daily/` unless overridden
  via `.vibe-kit-version.daily_log_dir`.

**Porting checklist:**
1. Pick the daily-log location. JP uses `workspace/memory/daily/YYYY-MM-DD.md`.
   Vibe-kit uses per-project unless told otherwise.
2. Decide on collision. Vibe-kit appends; JP-style setups can also
   append since their daily log is already a multi-event timeline.

---

## Pattern 6 — Score-based briefing surfacing (MEMORY.md style)

**Problem.** Session-start briefings can only fit so much in context.
Picking the wrong files to surface wastes budget; picking the right
ones is gold.

**Solution shape.** Don't keyword-match against an index file. Use a
score function:

- Filename + topic keyword from current task
- Recency (modified within N days)
- Frontmatter tag overlap with current repo / project
- Optional `repo:` frontmatter field for explicit repo scoping
- Length penalty (don't surface a 2000-line file just because it
  matched once)

Surface top-K. Truncate to the available context budget.

**Vibe-kit's reference impl:**
- v0.7.1 will land this for SessionStart hook when a workspace-wide
  index (like `memory/MEMORY.md`) is configured. Vibe-kit's per-project
  reference layer doesn't need this — the dir is already focused.

**Porting checklist:**
1. Pick the score function weights. Recency + tag overlap is a good
   start. Tune from there.
2. Pick the index format. MEMORY.md (one-line-per-file with hooks)
   is JP's shape; vibe-kit can read it directly if pointed at via
   `.vibe-kit-version.workspace_index`.

---

## What's NOT a pattern in vibe-kit

Things vibe-kit's reference impl does that you probably should NOT
port verbatim into a different stack:

- **Per-repo state dir.** `~/.vibe-kit/projects/<key>/` is the right
  shape for Claude Code's per-repo session model. Workspace-wide
  stacks should keep state in one workspace-truth dir. The patterns
  above all parameterize this — there's no per-repo assumption in
  Pattern 1, 2, 3, 5.
- **Block-hash CLAUDE.md merging.** Specific to Claude Code's CLAUDE.md
  convention. JP-style stacks read context from MEMORY.md directly;
  no merge needed.
- **gbrain as the search layer.** vibe-kit has affinity with gbrain
  because both are Yahya/Garry's tools. Other stacks (memmap+numpy,
  Qdrant, Weaviate, whatever) work fine — Pattern 1's nudge just
  needs to know the equivalent of "is markdown stale" for the
  configured backend.

---

## See also

- [`README.md`](../README.md) — Claude Code reference install instructions
- [`CHANGELOG.md`](../CHANGELOG.md) — design narrative version-by-version
- [`docs/design/batch-and-relay-protocol.md`](design/batch-and-relay-protocol.md) — Pattern 4 spec
- [`hooks/`](../hooks/) — Pattern 1's reference implementation
- [`skill/vibe-wrap/SKILL.md`](../skill/vibe-wrap/SKILL.md) — Pattern 2's reference implementation
