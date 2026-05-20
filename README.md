# vibe-kit

**Methodology for end-to-end AI coding workflow** + a reference implementation
for Claude Code.

vibe-kit is a small set of patterns that catch the work that falls through
the cracks during long AI-assisted coding sessions — context loss between
sessions, in-progress tasks that rot, search indexes that go stale, hand-offs
that never get written. The patterns are portable across agent stacks.

The reference implementation in this repo is Claude Code-only (skills + hooks +
a bash CLI). If you run a different stack — OpenClaw with workspace-wide
markdown memory, Cursor with manual notes, a custom Python harness — read
[`docs/PATTERNS.md`](docs/PATTERNS.md) and port the patterns into your setup
instead of installing vibe-kit.

Current version: **v0.7.0**. See [CHANGELOG.md](CHANGELOG.md) for the design
narrative version-by-version.

## The patterns

| # | Pattern | What it solves |
|---|---|---|
| 1 | [Per-turn nudge](docs/PATTERNS.md#pattern-1) | Agent edits files and forgets to sync downstream systems (task tracker, vector index, daily log) |
| 2 | [Session-wrap ritual](docs/PATTERNS.md#pattern-2) | End-of-session work falls through: tasks stay in-progress, no handoff written, next session starts blind |
| 3 | [Confidential-path autodetect](docs/PATTERNS.md#pattern-3) | Handoff stubs leak secrets when sessions touched credentials/vault dirs |
| 4 | [Batch-and-relay for non-interactive contexts](docs/PATTERNS.md#pattern-4) | Interactive skills hang forever when the human is in Telegram (orchestrator spawns Claude Code) |
| 5 | [Daily-line summary](docs/PATTERNS.md#pattern-5) | Per-session granularity matters for weekly retro but daily reflection loses it |
| 6 | [Score-based briefing surfacing](docs/PATTERNS.md#pattern-6) | Session-start briefing surfaces the wrong files because keyword-match is too crude |

Patterns 1 + 2 are shipping in vibe-kit today (reference impl in `hooks/` and
`skill/`). Patterns 3, 4, 5, 6 are designed (see `docs/`); reference impl lands
in v0.7.1.

## Use it (Claude Code reference install)

```bash
git clone https://github.com/myi1/vibe-kit ~/dev/vibe-kit
cd ~/dev/vibe-kit
bash bin/install.sh                    # writes wrapper + registers 4 skills
bash bin/install.sh --enable-all-hooks # wire all 3 Claude Code hooks (recommended)
```

Then in any repo you want to retrofit:

```bash
cd ~/your/repo
vibe-retrofit discover                 # read-only scan
# Or in a Claude Code session, just type:
#   /vibe-retrofit
```

Seven skills installed:
- `/vibe-retrofit` — interactive retrofit (the main entry)
- `/vibe-start` — on-demand session-start ritual (now surfaces board state)
- `/vibe-wrap` — end-of-session lifecycle (Pattern 2)
- `/vibe-upgrade` — keep vibe-kit current
- `/vibe-bug` — report a vibe-kit defect (auto-file opt-in)
- `/vibe-constitution` — establish project invariants (the drift anchor, v0.9)
- `/vibe-check` — pre-implement consistency gate against the constitution (v0.9)

Three hooks wired:
- **SessionStart** — auto-loads vibe-kit briefing per repo; nudges if vibe-kit is outdated; surfaces the constitution
- **PostToolUse** — Pattern 1 silent file-change logger
- **UserPromptSubmit** — Pattern 1 nudge injector

The board (v0.10):
```bash
vibe-retrofit board --open    # live read-only kanban over Taskmaster + PRs + commitments + specs
vibe-retrofit board --json    # the same data as JSON (also feeds /vibe-start)
```

Daily use: `/vibe-start` to load context (+ board state), `/vibe-check` before non-trivial
work, build, `/vibe-wrap` at end-of-session. Per-turn nudges fire automatically (disable
with `vibe-retrofit per-turn-sync off` if noisy).

## Port it (any other stack)

Don't install. Read [`docs/PATTERNS.md`](docs/PATTERNS.md) — each pattern has a
porting checklist. Two starter-kit extracted impls under
[`patterns/`](patterns/):

- [`patterns/per-turn-nudge/`](patterns/per-turn-nudge/) — Pattern 1 hooks with env-var configurable state dir, no vibe-kit dependencies. Copy + rename.
- [`patterns/session-wrap-ritual/`](patterns/session-wrap-ritual/) — Pattern 2 methodology guide (LLM-platform-agnostic). Walk the 6 phases, map I/O to your stack's task tracker / search backend / handoff location.

## Requirements (reference install)

- macOS or Linux
- bash 3.2+ (Apple stock works)
- git, jq, shasum or sha256sum
- For Tier 3 retrofits: [task-master-ai](https://github.com/eyaltoledano/claude-task-master) (`npm i -g task-master-ai`) + an AI provider key (`OPENAI_API_KEY` or similar — vibe-kit auto-detects)
- For optional vector search integration: [gbrain](https://github.com/garrytan/gbrain)

## Architecture (one paragraph)

**Skill owns intelligence, CLI owns primitives** (v0.3 architectural pivot). The
`/vibe-retrofit` skill drives interactive Q&A → draft → approve loops for each
scaffold file. The `bin/vibe-retrofit` bash CLI provides primitives the skill
calls: `discover`, `cluster-todos`, `probe-ai-keys`, `taskmaster-configure`,
`taskmaster-parse-prd`, `upgrade`, `per-turn-sync`. The skill never asks the
user to fill in a blank template; it always drafts first and shows for
approval. The reference layer (gstack-learnings, design docs, CEO plans,
handoffs) lives in a global per-project dir at
`~/.vibe-kit/projects/<project_key>/` so it's branch-independent (v0.2
pivot).

## License

[MIT](LICENSE)

## Versioning

- Stable command surface: `vibe-retrofit discover|merge-claude-md|write-version|doctor|rollback|migrate-to-global|upgrade|per-turn-sync|tier`
- Stable hook protocol: SessionStart, PostToolUse, UserPromptSubmit (Claude Code)
- Stable pattern doc: `docs/PATTERNS.md`
- Stable batch-and-relay protocol: `docs/design/batch-and-relay-protocol.md` (schema_version: 1)

Minor versions add patterns / primitives without removing existing ones. Major
versions are reserved for protocol incompatibilities.
