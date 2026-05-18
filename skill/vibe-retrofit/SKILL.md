---
name: vibe-retrofit
description: Rescue an existing AI-coded repo. Discovers scattered context (CLAUDE.md customizations, plan docs, TODO scatter, third-party libs), classifies it, and retrofits the repo with a session ritual + Taskmaster + standardized planning docs. Use when the user says "rescue this repo", "vibe-retrofit", "set up vibe-kit here", or runs `/vibe-retrofit`.
---

# /vibe-retrofit — orchestrator for vibe-kit retrofit

This skill is the conversational orchestrator that pairs with `bin/vibe-retrofit`. The script handles deterministic operations (file IO, hashing, git, taskmaster CLI calls). This skill handles the parts where a model adds real value over regex: classifying existing CLAUDE.md content, proposing triage classifications for discovered plan docs, authoring the synthetic PRD that Taskmaster's `parse-prd` will consume.

Handoff between skill and script is **file-based**:
- Script writes `.vibe-kit-discovery.json` (machine) + `.vibe-kit-discovery.md` (human)
- Skill writes `.vibe-kit-classification.json` (machine, optional — script falls back to bare templates if absent)

## Phase 1 — Pre-flight

Run via the Bash tool:

```bash
# 1. Confirm we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repo"; exit 1
fi
echo "REPO: $(basename "$(git rev-parse --show-toplevel)")"
echo "BRANCH: $(git branch --show-current)"
git status --porcelain | head -5
echo "---"
# 2. Check vibe-retrofit is installed
which vibe-retrofit || echo "ERROR: vibe-retrofit not on PATH. Run ~/dev/vibe-kit/bin/install.sh"
vibe-retrofit version 2>/dev/null | head -2
echo "---"
# 3. Check API key availability for Tier 3
[ -n "${OPENAI_API_KEY:-}" ] && echo "OPENAI_API_KEY: set"
[ -n "${ANTHROPIC_API_KEY:-}" ] && echo "ANTHROPIC_API_KEY: set"
[ -n "${PERPLEXITY_API_KEY:-}" ] && echo "PERPLEXITY_API_KEY: set"
[ -z "${OPENAI_API_KEY:-}${ANTHROPIC_API_KEY:-}${PERPLEXITY_API_KEY:-}" ] && echo "NO API KEY: Tier 3 will fail"
```

**Stop conditions:**
- Not in a git repo → tell user, stop
- Working tree has uncommitted changes to `CLAUDE.md` or `docs/vibe-kit/` → tell user to commit/stash first, stop
- `vibe-retrofit` not on PATH → tell user to run `~/dev/vibe-kit/bin/install.sh`, stop

If pre-flight passes: tell the user what was detected in one sentence and continue.

## Phase 2 — Discovery

Run `vibe-retrofit discover` to scan the repo. This is read-only — no risk.

```bash
vibe-retrofit discover
```

Then read the generated reports:

```bash
cat .vibe-kit-discovery.json
echo "---"
head -50 .vibe-kit-discovery.md
```

**Summarize the findings for the user in 4-6 lines**: how many agent files, how many plan docs, how many TODOs, how many libraries, whether Taskmaster is already initialized. Be specific (counts + a sample of the top items). End with: "Read the full report at `.vibe-kit-discovery.md` if you want detail. Otherwise, ready to pick a tier?"

## Phase 3 — Tier selection

Use AskUserQuestion to confirm tier. Default is Tier 3 for repos with felt pain.

> "Which tier? Tier 1 = CLAUDE.md merge only (10 min). Tier 2 = + docs/vibe-kit/ scaffolds with discovered-doc pointers (45 min). Tier 3 = + Taskmaster init with TODOs imported via parse-prd (2-3 hrs human / ~$0.0005 OpenAI cost). Default Tier 3 for rescue use case."

Options:
- A) Tier 3 — full retrofit (recommended for rescue)
- B) Tier 2 — standard
- C) Tier 1 — minimum
- D) Dry-run first (run `vibe-retrofit tier <chosen> --dry-run` to preview before committing)

If user picks D, run `vibe-retrofit tier <N> --dry-run`, show output, then re-ask if they want to apply.

## Phase 4 — Skill's fuzzy work (Tier 2+ only)

For Tier 2 and Tier 3, before invoking the tier orchestrator, do the classification work the bash script can't do well:

### 4a. Classify existing CLAUDE.md content (if CLAUDE.md exists pre-retrofit)

Read the existing CLAUDE.md (if any) and bucket each section into one of:
- `commands` — install/test/typecheck/dev commands (might overlap with vibe-kit's Commands section)
- `routing` — skill or command routing (might overlap with vibe-kit's Skill routing section)
- `conventions` — code style, patterns, project conventions (KEEP as-is, doesn't overlap with vibe-kit)
- `other` — anything else (project description, contact info, links — KEEP as-is)

**Tell the user**: "Your existing CLAUDE.md has N sections. I classified them as: [breakdown]. The vibe-kit additions block will be appended at the end — your existing commands/routing sections will REMAIN above it. You may want to consolidate later, but the retrofit won't touch them."

### 4b. Triage discovered plan docs (Tier 2+)

For each plan doc in `.vibe-kit-discovery.json` `.plan_docs[]`, propose a triage classification:
- `load-bearing` — linked from PROJECT_MAP.md
- `reference` — moved to `docs/vibe-kit/reference/`
- `stale` — moved to `docs/archive/` with one-line death note

To classify, read the first 30 lines of each doc and apply judgment:
- Recent date stamp + active TODOs + concrete file references → load-bearing
- Pure documentation / how-tos / "here's how the system works" → reference
- "Plan to migrate X by Q3 2024" or older + no follow-up → stale

Present the triage proposal in a table:

| Doc | Proposed | Why |
|-----|----------|-----|
| docs/plans/auth-flow.md | load-bearing | Active TODOs, references current files |
| thoughts/2024-q3-refactor.md | stale | Date is 2 years old, refactor never happened |
| docs/api-conventions.md | reference | Stable reference docs, no decay |

Ask the user to confirm or override before any moves happen. **Do not move files yet** — write the classification to `.vibe-kit-classification.json` so the tier orchestrator can use it.

```bash
# Build the classification JSON (after user confirms)
jq -n '{
  plan_doc_triage: [
    {"path": "docs/plans/auth-flow.md", "classification": "load-bearing"},
    {"path": "thoughts/2024-q3-refactor.md", "classification": "stale"},
    {"path": "docs/api-conventions.md", "classification": "reference"}
  ]
}' > .vibe-kit-classification.json
```

### 4c. Author synthetic PRD (Tier 3 only)

`vibe-retrofit init-taskmaster` builds a default synthetic PRD from raw discovered TODOs. The skill can do better: read `.vibe-kit-discovery.json` `.todos[]` and group them by module/area before feeding to parse-prd. This improves the quality of Taskmaster's task generation.

If TODO count is < 30: no grouping needed, the bare PRD from the script is fine.

If TODO count is 30+: group by file directory, write a curated PRD to `.vibe-kit-synthetic-prd.md`, and tell the script to use it instead (the script will respect a pre-existing file at that path).

## Phase 5 — Execute the tier

Run the tier orchestrator. Pass `--dry-run` first if the user asked for it in Phase 3.

```bash
vibe-retrofit tier <N>
```

The script handles: CLAUDE.md merge (idempotent, refuses if block hash mismatches), docs/vibe-kit/ scaffold writes, Taskmaster init + parse-prd, .vibe-kit-version write, single commit on `vibe-kit-retrofit` branch.

## Phase 6 — Triage gate (after Tier 3 only)

After `task-master parse-prd` runs, **stop and triage** before the user moves on. Show:

```bash
task-master list --status=pending | head -30
echo "---"
echo "Total pending:"
task-master list --status=pending --format=compact 2>/dev/null | wc -l
```

Tell the user: "Taskmaster imported N tasks. Triage by recognition:
- Anything you don't recognize → `task-master remove-task --id=<id>`
- Anything stale but worth keeping → `task-master set-status <id> deferred` and tag `stale:?`
- Anything live → leave or `task-master set-status <id> in-progress`

Take 15-30 min on this. Bad Taskmaster output now becomes a graveyard later."

Then, for accepted plan-doc moves from Phase 4b, propose them:

```bash
# (Only if user approved moves in Phase 4b)
# For each load-bearing doc: ensure it's linked from docs/vibe-kit/PROJECT_MAP.md
# For each reference doc: mv "$src" "docs/vibe-kit/reference/$(basename "$src")"
# For each stale doc:     mv "$src" "docs/archive/$(basename "$src")"
```

Do these moves only with explicit user approval. Default to NOT moving — the retrofit can be repeated later.

## Phase 7 — Report + handoff

Tell the user:
1. **What changed**: CLAUDE.md updated, docs/vibe-kit/ scaffolded with N files, .vibe-kit-version written (tier N), Taskmaster initialized with M tasks (or "no Taskmaster" for Tier <3).
2. **Branch**: `vibe-kit-retrofit` — review the diff, squash-merge to main when ready (or `vibe-retrofit rollback` if you want to undo).
3. **Next steps**: Read `sop/SESSION_RITUAL.md` from your vibe-kit clone. Open `KNOWN_GOTCHAS.md` and add one entry once the verification gate catches its first bug. Run `vibe-retrofit doctor` weekly.

## Pre-flight failures — error messages

If `merge-claude-md` returns "Block hash mismatch": user edited inside the marker block. Choices:
- Move custom edits ABOVE the marker, re-run
- Or `vibe-retrofit tier <N> --force` (overwrites the block; user accepts loss of in-block edits)

If `init-taskmaster` returns "No LLM API key": tell user to set OPENAI_API_KEY in shell, then re-run only `vibe-retrofit init-taskmaster` (no need to redo discover/merge).

If discovery finds `>500 TODOs`: warn the user — parse-prd cost scales linearly (~$0.0001/task = ~$0.05 for 500). Offer Phase 4c grouping to compress.

## Posture

- Always interactive — never destructive. Every mutating step gates on user confirmation.
- Commits to `vibe-kit-retrofit` branch — squash-merge after review.
- Never modifies files outside the standard scope (CLAUDE.md, .vibe-kit-version, docs/vibe-kit/, .taskmaster/). Plan-doc moves only with explicit per-doc approval.

## Completion

Report DONE with: tier executed, files touched, taskmaster task count, branch name, rollback hint.

Report DONE_WITH_CONCERNS if: parse-prd produced obviously hallucinated tasks (named entities not in the discovered TODOs), CLAUDE.md merge produced visible duplication, OR user declined a step that's load-bearing for the tier.

Report BLOCKED if: pre-flight failed and the user can't resolve it in this session.
