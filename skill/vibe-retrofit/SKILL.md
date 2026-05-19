---
name: vibe-retrofit
description: Rescue an existing AI-coded repo. Discovers scattered context (CLAUDE.md customizations, plan docs, TODO scatter, third-party libs), then interactively drafts real scaffolds with Q&A (not empty stubs) and curates TODOs into a focused PRD before importing into Taskmaster. Use when the user says "rescue this repo", "vibe-retrofit", "set up vibe-kit here", or runs `/vibe-retrofit`.
---

# /vibe-retrofit — orchestrator for vibe-kit retrofit (v0.3+)

This skill is the conversational orchestrator that pairs with `bin/vibe-retrofit`. The CLI handles deterministic operations (file IO, hashing, git, taskmaster CLI calls, JSON data transforms). This skill handles every part where a model adds real value over regex: drafting the docs/vibe-kit scaffolds from Q&A (not empty stubs), curating raw TODOs into a focused PRD (not a 100-noisy-tasks dump), picking the right AI provider for Taskmaster (not blindly defaulting to Anthropic).

**The split is the architecture.** Bash does mechanical work. Skill does intelligent work. If you find yourself reaching for a bash helper that takes free-form user input, that's a skill phase, not a bash subcommand.

**Handoff is file-based:**
- CLI writes `.vibe-kit-discovery.json` (machine-readable)
- CLI primitives accept `--json` so the skill can parse + drive the conversation
- Skill writes draft files directly via the Write tool (no template-copy)
- Skill writes `.vibe-kit/curated-prd.md` (Tier 3) for `taskmaster-parse-prd` to consume

---

## Phase 1 — Pre-flight

```bash
# Confirm git repo + clean working tree on the targets we'll touch
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: not in a git repo"; exit 1; }
echo "REPO:   $(basename "$(git rev-parse --show-toplevel)")"
echo "BRANCH: $(git branch --show-current)"
git status --short | head -10
echo "---"
# Confirm vibe-retrofit on PATH + version
command -v vibe-retrofit >/dev/null 2>&1 || { echo "ERROR: vibe-retrofit not on PATH — run ~/dev/vibe-kit/bin/install.sh"; exit 1; }
vibe-retrofit version | head -2
```

**Stop conditions:**
- Not in a git repo → tell user, stop.
- Uncommitted changes to `CLAUDE.md`, `docs/vibe-kit/`, `.vibe-kit-version`, `.taskmaster/` → tell user to commit/stash first.
- `vibe-retrofit` not on PATH → tell user to run the install script.
- vibe-retrofit version < 0.3 → tell user to `cd ~/dev/vibe-kit && git pull && bash bin/install.sh` first.

If pre-flight passes, continue silently — don't bloat output with a green-check report.

---

## Phase 2 — Discovery

```bash
vibe-retrofit discover
```

Read the JSON (not the human report — you'll synthesize your own summary):

```bash
cat .vibe-kit-discovery.json | jq '{
  agent_files: (.agent_files // [] | length),
  plan_docs: (.plan_docs // [] | length),
  todo_count: .todo_count,
  libraries: (.libraries // [] | length),
  gstack_artifacts: ((.gstack.designs + .gstack.ceo_plans + .gstack.checkpoints + .gstack.handoffs + .gstack.autoplans + .gstack.test_plans) // [] | length),
  taskmaster_present: ((.taskmaster // false) | not | not)
}'
```

**Tell the user in 3-5 lines max:** counts of each artifact type + whether Taskmaster is already initialized + 1-2 most interesting findings (e.g. "Found 24 gstack artifacts under ~/.gstack/projects/yahyaismail — your prior work on this repo").

---

## Phase 3 — Discovery review (CRITICAL — this catches the script's blind spots)

The discovery scan uses regex heuristics. It misses things. Ask the user **before** drafting anything:

> "Discovery found these context-holding directories: [list from .agent_files and .plan_docs and top-level dirs]. Are there any IMPORTANT subdirs it missed? Things like `apps/<app>/docs/<system>/`, internal wikis, design libraries, ADR folders — places where load-bearing context lives but the script wouldn't have found via top-level scan."

Collect the user's answer. Cache it in memory — you'll use it in:
- Phase 6 (scaffold authoring) — thread these dirs into the PROJECT_MAP "Important context dirs" slot
- Phase 9 (commit) — note them as discovery follow-ups

If the user names a dir like `apps/hub-portal/docs/hubibi/`, briefly verify it exists with `ls` and skim the top 1-2 files so your later draft references real content.

---

## Phase 4 — Tier selection

Use AskUserQuestion. Default Tier 3.

> "Which tier?
> Tier 1 = CLAUDE.md merge only (5 min, no API cost)
> Tier 2 = + interactive Q&A-driven scaffolds in docs/vibe-kit/ + gstack reference symlinks (10-15 min, no API cost)
> Tier 3 = + curated TODO PRD → Taskmaster import (15-25 min, ~$0.01-0.05 API cost)
> Default: Tier 3 for rescue use case."

Options: Tier 3 (Recommended) / Tier 2 / Tier 1 / Cancel.

---

## Phase 5 — CLAUDE.md merge (all tiers)

Briefly read existing CLAUDE.md (if any) and tell the user how many sections it has and what they cover. Don't classify exhaustively — the vibe-kit additions block is appended at the end and doesn't touch existing content unless block-hash mismatch (in which case bash refuses and the user decides --force or move-edits-up).

```bash
vibe-retrofit merge-claude-md
```

If the script refuses because of a hash mismatch, tell the user the two options (move edits above marker / `--force`) and let them pick.

---

## Phase 6 — Scaffold authoring (Tier 2+) — Q&A draft pass

**This is where v0.3 stops writing empty stubs and starts producing real docs.**

For each template in `~/dev/vibe-kit/templates/docs/vibe-kit/*.tmpl`:

1. Read the template file with the Read tool.
2. Extract the prompt block — everything between `<!-- VIBE-KIT:PROMPT-BLOCK-START` and `VIBE-KIT:PROMPT-BLOCK-END -->`. The block tells you what questions to ask the user.
3. Ask the questions **conversationally and one at a time** (or batched 2-3 per AskUserQuestion call if they're closely related). Prime each question with the relevant discovery context the prompt block calls out (e.g. for ARCHITECTURE's "shape" question, prime with the detected libraries).
4. Draft the answers into the `{{SLOT_*}}` placeholders. Strip the prompt block. Substitute `{{project_name}}` and `{{retrofitted_at}}`.
5. Show the rendered file to the user with: "Here's the draft for `docs/vibe-kit/<file>`. Approve as-is, edit any section, or skip the file?"
6. Iterate until the user approves. Then Write the file to `docs/vibe-kit/<file>`.

**Order to draft them in:** PROJECT_MAP.md → ARCHITECTURE.md → TESTING.md → RETROS.md. (PROJECT_MAP first because it grounds the user; ARCHITECTURE builds on it; TESTING is concrete; RETROS is just a format spec with no Q&A.)

Also draft `KNOWN_GOTCHAS.md` at the repo root if it doesn't exist — but here the Q&A is short ("Any project quirks you want to flag right now? Things that have bitten you before that future-you should know?"). If user has nothing, write a minimal scaffold with the section format and a note that `/learn` will populate it over time.

**Posture during Q&A:**
- Ask 1-2 questions per turn. Don't dump 8 questions at once.
- Quote the user's answer verbatim when drafting — don't paraphrase unless asked.
- If the user gives a one-word answer, gently expand with a clarifying question rather than producing a one-word section.
- If the user says "skip" on a section, leave the slot as `_(skipped — fill in later)_` and move on. No shame.

---

## Phase 7 — gstack reference symlinks (Tier 2+)

Deterministic — just invoke the primitive:

```bash
vibe-retrofit _scaffold_gstack_reference 2>/dev/null || true
# Actually: tier-2/tier-3 orchestrator runs this internally as part of the
# `_scaffold_gstack_reference` helper. We don't expose it as a top-level
# subcommand because it's pure mechanical work after the global-dir resolution.
# Just rely on cmd_tier to call it, or run `vibe-retrofit tier 2 --dry-run`
# to see what would land.
```

Actually the v0.3 way: call `vibe-retrofit tier <N>` AT THE END (Phase 10), not here. Tier orchestrator runs the deterministic phases (`_scaffold_gstack_reference`, `write-version`). The skill has already done the intelligent phases (CLAUDE.md merge in Phase 5, scaffold drafting in Phase 6).

Skip this phase in v0.3 — fold it into Phase 10.

---

## Phase 8 — TODO curation (Tier 3 only)

**Replaces the v0.2 "dump 108 raw TODOs at parse-prd, get 108 noisy tasks" anti-pattern.**

```bash
vibe-retrofit cluster-todos --json > /tmp/vibe-todo-clusters.json
cat /tmp/vibe-todo-clusters.json | jq '.clusters | map({name, count, total_files, keyword_breakdown})'
```

Tell the user:
> "Discovery found N TODOs across M files. I've clustered them into K groups by directory + keyword. For each cluster I'll show you the sample TODOs and you tell me: keep all / keep some / drop all / I'll specify."

**Per-cluster walkthrough:**

For each cluster (largest first, capped at top 10 clusters for sanity):
1. Show: cluster name, count, keyword breakdown, top 3-5 sample TODOs verbatim.
2. Ask via AskUserQuestion:
   - "Keep all (X TODOs)"
   - "Drop all (you've outgrown / never going to do)"
   - "Keep some — I'll specify which" (then ask follow-up about which line numbers / patterns)
   - "Skip cluster review, I'll triage in Taskmaster later"
3. Collect: list of `{file, line, text}` entries the user wants to keep.

After all clusters reviewed (or user opts to skip remaining), write the curated PRD:

```bash
mkdir -p .vibe-kit
cat > .vibe-kit/curated-prd.md <<EOF
# Curated work backlog — $(basename "$(pwd)")

Curated by /vibe-retrofit on $(date -u +%Y-%m-%dT%H:%M:%SZ) from N raw TODOs
across M clusters. Only items the user explicitly kept are below. Each
becomes one Taskmaster task; preserve file:line provenance.

## Tasks

$(... user-kept TODOs as bullets, grouped by cluster ...)
EOF
```

Tell the user how many TODOs survived curation. Realistic compression: 100+ raw → 15-30 curated is the target.

---

## Phase 9 — Taskmaster setup (Tier 3 only) — provider + cost confirm

**Probe available AI keys:**

```bash
vibe-retrofit probe-ai-keys --json > /tmp/vibe-ai-keys.json
cat /tmp/vibe-ai-keys.json | jq
```

Use the JSON to drive an AskUserQuestion:

> "I found these AI provider keys: [list available ones with sources]. Taskmaster needs one provider for main/research/fallback model. Recommended: <X> (it's cheap for bulk PRD parsing). Cost estimate for your curated PRD: ~$<estimate>.
>
> Use <recommended>? Or pick a different available provider?"

Options (only show options the user actually has keys for):
- Use <recommended> (Recommended)
- Use <other_available>
- Skip Taskmaster setup (do it manually later)
- Cancel retrofit

**On user confirm:** if the key is in a shell rc file but NOT in the current env, `source` it explicitly before continuing. Then:

```bash
# IMPORTANT: source the rc file if the key was detected there but not in env.
# vibe-retrofit's probe-ai-keys output names the source file.
source ~/.zshrc 2>/dev/null  # or whichever file the probe found

vibe-retrofit taskmaster-configure --provider <chosen>
vibe-retrofit taskmaster-parse-prd --prd .vibe-kit/curated-prd.md
```

Show the user the imported task count + a sample of the first 5 tasks (`task-master list --status=pending | head -10`).

---

## Phase 10 — Finalize

Run the deterministic tail of the retrofit:

```bash
# gstack reference symlinks (global location, branch-independent — v0.2+)
# This is folded into `vibe-retrofit tier <N>` but the scaffold-drafting
# phase has already produced the docs/vibe-kit/*.md files, so the tier
# orchestrator will skip them (they exist) and only write _scaffold_gstack_reference.
vibe-retrofit tier <N>

# .vibe-kit-version is written automatically by the tier orchestrator.
```

**Final summary** to the user:
1. **What changed:** CLAUDE.md updated (block hash <8-char>), docs/vibe-kit/ has N curated files, gstack reference symlinked to global location, .vibe-kit-version written (tier N, project_key <X>).
2. **Taskmaster (Tier 3):** N tasks imported from curated PRD via <provider>. Run `task-master list` to inspect. Run `task-master next` to start working.
3. **Branch:** `vibe-kit-retrofit` (or the current branch if you started on a non-main branch). Review the diff, squash-merge to main when ready. Rollback via `vibe-retrofit rollback` if anything looks off.
4. **Verify:** Open a fresh Claude Code session in this repo. The vibe-kit SessionStart hook should fire with a briefing pulling from `~/.vibe-kit/projects/<project_key>/reference/`. If the briefing is missing, run `vibe-retrofit doctor`.

---

## Error handling

- `merge-claude-md` returns "Block hash mismatch" → tell user: move edits above marker, or `--force` (loses in-block edits).
- `taskmaster-parse-prd` returns API auth error → tell user the key source file probably needs to be sourced into env; show the exact `source` command.
- `cluster-todos` shows huge "other" cluster → the path-based clustering didn't find good groupings (likely a flat-layout repo); fall back to keyword-based filtering ("keep all FIXME, drop all TODOs" type prompt).
- Discovery missed important dirs (caught in Phase 3) but user already approved → no problem, you'll thread them into the scaffolds in Phase 6.

---

## Posture (v0.3 reminder)

- **Interactive by default.** Every mutating step gates on user confirmation.
- **Skill drives intelligence.** If you find yourself reaching for a bash helper to do free-form text generation or classification, the skill should do it, not bash.
- **Drafts shown for approval.** Never write a scaffold without the user approving the content first.
- **Curation before import.** Never `parse-prd` a raw TODO dump. Always cluster + walk + write a curated PRD first.
- **Provider auto-detect.** Never assume Taskmaster's default provider. Always probe + confirm.

---

## Completion reports

- **DONE** — tier N executed, all scaffolds drafted + approved, Taskmaster (if Tier 3) imported M tasks from N raw TODOs (compression ratio noted), branch + rollback hint surfaced.
- **DONE_WITH_CONCERNS** — user skipped a scaffold OR cluster review, OR curated PRD compression was low (<3x), OR a discovered dir from Phase 3 didn't make it into PROJECT_MAP.
- **BLOCKED** — pre-flight failed and user can't resolve in-session, OR vibe-retrofit version too old.

## Bug detection (v0.8.0)

If during this skill a vibe-kit defect surfaces — bash primitive returns malformed JSON, referenced file/command doesn't exist, skill leaves user in partial state despite all preconditions met, or you couldn't make progress despite documented prerequisites — invoke `/vibe-bug` via the Skill tool with the trigger context (skill name, what failed, expected vs actual). `/vibe-bug` handles drafting + filing/local-save. Don't silently work around. NOT a trigger: missing API keys, dirty git tree (expected refusal), missing optional deps (gbrain/taskmaster — skill is supposed to skip). See `skill/vibe-bug/SKILL.md` for the full trigger rubric.
