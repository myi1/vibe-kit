# Changelog

All notable changes to vibe-kit are documented in this file. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-05-19 (Skill owns intelligence, CLI owns primitives — real scaffolds + curated tasks + auto-provider)

**Three bugs drove this release**, all reported from a real Tier 3 retrofit on a 108-TODO repo:

1. **Scaffolds were empty stubs.** `docs/vibe-kit/{PROJECT_MAP,ARCHITECTURE,TESTING,RETROS}.md` got written as TODO-yourself templates. The user had to fill them in by hand. Nothing in the retrofit actually USED the LLM to draft them. Other gstack skills (office-hours, plan-ceo-review) do interactive Q&A → draft → approve. Vibe-kit didn't.
2. **Taskmaster defaulted to Anthropic, every retrofit had to be manually reconfigured.** The user has `OPENAI_API_KEY` (the common case), the script ran `task-master init` without provider detection, and `parse-prd` failed loud demanding an Anthropic key. User had to run `task-master models --setMain/Research/Fallback` manually three times before parse-prd would work.
3. **108 TODOs in → 108 noisy tasks out.** `parse-prd` doesn't dedupe, doesn't cluster, doesn't prioritize. It's 1:1 TODO→task. The retrofit report literally noted "expected outcome: the 108 tasks are noisy — many are duplicates, stale, or trivially-resolved file:line references." The fix should have happened at ingest, not as a follow-up cleanup.

**The common architectural fix:** vibe-kit's CLI keeps doing mechanical work (marker-bounded merges, hashing, file IO). Everything that requires asking the user a question or producing a draft moves into the `/vibe-retrofit` SKILL. Same separation gstack uses everywhere — and the reason gstack feels different from vibe-kit when you use them back to back.

### Added — 4 new CLI primitives (skill-driven)

- **`vibe-retrofit probe-ai-keys [--json]`** — detects which provider keys are available, in env vars AND in shell rc files (`~/.zshrc`, `~/.bashrc`, etc.). Never echoes the key value, only the var name + source. Recommends the cheapest available provider for Taskmaster.
- **`vibe-retrofit cluster-todos [--json]`** — pure data transform over the discovery JSON's TODOs. Groups by directory + keyword (TODO/FIXME/HACK/XXX), caps at 20 clusters, sample TODOs per cluster. The skill walks the user through each cluster (keep/drop/dedupe) before any task import.
- **`vibe-retrofit taskmaster-configure --provider <name>`** — sets Taskmaster main/research/fallback for the chosen provider with cheap-model defaults (openai → gpt-4o-mini, anthropic → claude-haiku-4-5, google → gemini-1.5-flash, etc.). Tries `--setMain` (camelCase) first, falls back to `--set-main` (kebab-case) for older task-master versions. Idempotent.
- **`vibe-retrofit taskmaster-parse-prd --prd <file>`** — wraps `task-master init` (idempotent) + `task-master parse-prd --input=<file>`. The skill writes a CURATED PRD here, not raw TODOs.

### Changed — SKILL.md rewritten as full orchestrator

The `/vibe-retrofit` skill now drives the entire retrofit interactively:

- **Phase 3 (NEW): Discovery review.** Skill asks the user "did discovery miss any important subdirs?" — catches the class of misses where the script's heuristics don't find e.g. `apps/<app>/docs/<system>/`. The original retrofit report flagged exactly this miss as the single highest-value follow-up; now it's caught at retrofit time.
- **Phase 6 (NEW): Scaffold authoring with Q&A.** For each of PROJECT_MAP/ARCHITECTURE/TESTING/RETROS, the skill reads the template's `<!-- VIBE-KIT:PROMPT-BLOCK -->` section to know what questions to ask, runs the Q&A conversationally (one or two questions per turn, primed with discovery context), drafts the file, shows the user for approval, iterates until signed off, writes. No more empty stubs.
- **Phase 8 (NEW): TODO curation.** Skill calls `cluster-todos --json`, walks the user through each cluster (largest first), collects which items to keep, writes `.vibe-kit/curated-prd.md` with only the kept items. Target compression: 100+ raw → 15-30 curated.
- **Phase 9 (NEW): Provider auto-detect + cost confirm.** Skill calls `probe-ai-keys --json`, recommends the cheapest available provider, shows a cost estimate for the curated PRD, asks the user to confirm (per their request: "after confirming with user to connect API key since theres a cost associated with it"). Sources the rc file into env if the key was detected there but not currently exported.

### Changed — templates are now skill-readable prompts, not literal content

Templates under `templates/docs/vibe-kit/*.tmpl` now lead with a `<!-- VIBE-KIT:PROMPT-BLOCK-START ... VIBE-KIT:PROMPT-BLOCK-END -->` section that tells the skill what questions to ask for each `{{SLOT_*}}` placeholder. The skill strips the block before writing the final file. The user-visible output is a real curated document, not a TODO-yourself stub.

### Migration

- **Existing pre-v0.3 retrofitted repos:** no migration needed. Their `.vibe-kit-version` + CLAUDE.md + docs/vibe-kit/* keep working as-is. To regenerate scaffolds with the new Q&A flow, re-run `/vibe-retrofit` (the skill detects the existing state and offers a "refresh scaffolds" path).
- **Existing users updating vibe-kit:** `cd ~/dev/vibe-kit && git pull && bash bin/install.sh` picks up the new CLI primitives + the rewritten SKILL.md.
- **The v0.2 `migrate-to-global` subcommand stays.** Still the right tool for pre-v0.2 retrofits that have an in-repo `docs/vibe-kit/reference/`.

### What this closes

Three "vibe-kit doesn't feel like gstack" complaints, one architectural fix. The CLI keeps being the mechanical foundation. The skill becomes the actual product surface — the conversational orchestrator users experience. The user's exact framing was right: "it should be the llm filling out the docs, then showing me for approval. like gstack does."

## [0.2.0] — 2026-05-19 (Reference layer moves outside the repo — branch-independent context)

**The bug that drove this release:** user's fresh Claude Code session on the canary repo couldn't see the vibe-kit briefing, because the canary's retrofit lived on a feature branch that hadn't merged to main. The SessionStart hook found `.vibe-kit-version` but the `docs/vibe-kit/reference/` it pointed at didn't exist on main yet. Re-initialize, lose context — the whole point of session-start was defeated by the worst possible thing: git branch state.

The fix is architectural: the reference layer (gstack-learnings, design docs, CEO plans, handoffs, checkpoints) now lives at `~/.vibe-kit/projects/<project_key>/reference/` — outside the repo entirely. The SessionStart hook resolves the path from a `project_key` field newly persisted into `.vibe-kit-version`. Every branch sees the same reference layer. Cloning a repo onto a new machine pulls only the branch-coupled artifacts (CLAUDE.md additions, KNOWN_GOTCHAS, .taskmaster) — no personal gstack history leaks across machines.

### Added
- **`vibe-retrofit migrate-to-global`** subcommand: one-shot migration for pre-v0.2 retrofitted repos. Detects in-repo `docs/vibe-kit/reference/`, rebuilds the bundle at `~/.vibe-kit/projects/<key>/reference/` from current discovery (not a stale copy), deletes the in-repo dir, leaves a pointer README at `docs/vibe-kit/README.md`, re-renders the CLAUDE.md block with global paths, and updates `.vibe-kit-version` with the new fields. Idempotent — safe to re-run; reports "Already migrated" if there's nothing to do. `--dry-run` supported.
- **`project_key` field in `.vibe-kit-version`** — defaults to `basename(cwd)`. Users with collision-prone repo names (e.g., multiple repos basename'd `frontend`) can edit it manually post-retrofit; subsequent re-runs preserve the override via `_resolve_project_key()`.
- **`global_reference_dir` field in `.vibe-kit-version`** — absolute path to the bundle, computed from `project_key`. Hook + CLAUDE.md template both consume this.
- **Helpers in `bin/vibe-retrofit`** — `_resolve_project_key()`, `_global_project_dir()`, `_global_reference_dir()`. Single source of truth.
- **README at `~/.vibe-kit/projects/<key>/reference/README.md`** explaining why the bundle lives outside the repo and how to refresh it (`vibe-retrofit tier 2` from the repo root).

### Changed
- **SessionStart hook (`hooks/vibe-kit-session-start.sh`)** reads `project_key` from `.vibe-kit-version` and resolves the global location instead of the prior in-repo `docs/vibe-kit/reference/`. Resolution precedence: explicit `global_reference_dir` field → `~/.vibe-kit/projects/<project_key>/reference/` → `~/.vibe-kit/projects/<basename-cwd>/reference/` → in-repo `docs/vibe-kit/reference/` (pre-v0.2 fallback, with a one-line nudge to run `vibe-retrofit migrate-to-global`).
- **CLAUDE.md template** now embeds the resolved global path so the session-start ritual instructions Claude sees point at the canonical out-of-repo location. New `{{project_key}}` and `{{global_reference_dir}}` substitutions handled by `cmd_merge_claude_md`.
- **`_scaffold_gstack_reference`** writes to the global location instead of `docs/vibe-kit/reference/`. The reference README explains the move + how to refresh.
- **Tier 2 and Tier 3 orchestrators** transparently use the global location. New retrofits get the v0.2 layout from day one.
- **`docs/vibe-kit/README.md` pointer** is the only vibe-kit artifact left in the docs/ tree post-migration. Tells anyone browsing the repo where the reference layer moved to and how to refresh it.

### Fixed
- **jq escape bug introduced mid-build:** the v0.2 reference README initially used `\\` (backslash-backtick) inside a jq string literal, which is not a valid jq escape. set -e killed the migration silently. Caught during smoke test, fixed before any user-visible release.

### Migration
1. **Existing users (no retrofitted repos yet):** `cd ~/dev/vibe-kit && git pull && bash bin/install.sh`. The wrapper + skills + hook refresh picks up v0.2. New retrofits are global by default.
2. **Existing retrofitted repos:** `cd <repo> && vibe-retrofit migrate-to-global`. One command, idempotent, ~1 second. Re-render of CLAUDE.md block happens automatically. Commit the resulting diff (`docs/vibe-kit/README.md` added, `docs/vibe-kit/reference/` removed, `CLAUDE.md` re-rendered, `.vibe-kit-version` rewritten).

### What this closes
v0.1 design assumed the retrofit commit would be on main when sessions opened. Real life: branches exist, retrofit lives on a branch, fresh sessions hit main, briefing breaks. v0.2 decouples the reference layer from git state entirely. The CLAUDE.md additions, KNOWN_GOTCHAS, and `.taskmaster/` stay in the repo because they SHOULD be branch-aware (different branches may have different agent guidance or task lists). The reference layer is institutional knowledge about the project, not about any specific branch — it belongs outside.

### Verified on canary
`remax-hub-portal` migrated end-to-end: 19 learnings, 10 design docs, 3 CEO plans, 2 checkpoints, 1 handoff, 4 autoplans, 7 test plans all symlinked into `~/.vibe-kit/projects/remax-hub-portal/reference/`. Hook briefing renders the top-3 learnings + recent handoff + most-recent CEO plan independent of which branch is checked out.

## [0.1.0-pre.8] — 2026-05-18 (/vibe-start skill + SessionStart hook)

Building on pre.7's "CLAUDE.md tells Claude what to do," adding two deterministic mechanisms so the user doesn't have to rely on Claude reading instructions.

### Added
- **`/vibe-start` skill** (`skill/vibe-start/SKILL.md`): on-demand deterministic session-start ritual. Runs pre-flight check, loads learnings, checks Taskmaster, lists recent designs/CEO plans/handoffs, surfaces KNOWN_GOTCHAS, ends with "What do you want to work on?". User can invoke explicitly via `/vibe-start` from a chat.
- **SessionStart hook** (`hooks/vibe-kit-session-start.sh`): runs automatically at the start of every Claude Code session if wired into `~/.claude/settings.json`. Detects `.vibe-kit-version` and emits a compact briefing (~15 lines) injected into Claude's session context. Silent no-op on non-retrofitted repos.
- **install.sh refactor:** now loops over `skill/*/SKILL.md` and installs each as a Claude Code skill. Also installs the SessionStart hook to `~/.claude/hooks/` AND offers an opt-in wiring step (`./bin/install.sh --enable-hook`) that updates `~/.claude/settings.json` via `jq` with a backup.

### Layout change
- `skill/SKILL.md` → `skill/vibe-retrofit/SKILL.md` (per-skill subdirectories now). install.sh still recognizes the legacy `skill/SKILL.md` path for back-compat with older installs.
- New `hooks/` directory at repo root.

### Migration
Existing users: `cd ~/dev/vibe-kit && git pull && ./bin/install.sh` picks up both new skills + installs the hook (without wiring it). Wire the hook in with `./bin/install.sh --enable-hook` (one-time, requires `jq`).

### What this closes
This is the deterministic + automatic answer to the muscle that pre.7 added. The pre.7 CLAUDE.md said "do the session-start ritual"; the pre.8 SessionStart hook actually runs the ritual without typing anything. Together: Claude has zero excuse to skip context loading on retrofitted repos.

## [0.1.0-pre.7] — 2026-05-18 (CLAUDE.md actually instructs Claude — the missing muscle)

User flagged the real gap after canary retrofit: "we built the bones for context + task tracking but didn't actually give the AI's vibe coding better context or task tracking." The retrofit was producing static artifacts (gstack-learnings.md, symlinks) but the CLAUDE.md block didn't tell Claude to USE them. Session behavior didn't change.

### Added
- **Imperative session-start ritual section in `CLAUDE.md.tmpl`.** Five steps Claude must execute before responding to the first request: read CLAUDE.md fully, read `docs/vibe-kit/reference/gstack-learnings.md`, run `task-master next` if `.taskmaster/` exists, scan relevant prior designs for the request's system area, and report "Loaded N learnings, M tasks, recent designs: …" in the first reply as proof the ritual ran.
- **Task tracking integration section.** Concrete instructions: list pending tasks before starting work; mark done on completion; capture new work via `add-task`; never invent priority order — always `task-master next` first.
- **Context7 section** moved out of "do not" list into its own block with explicit "tools appear as `mcp__context7__*`" guidance.
- **"Done means" expanded** to include "the Taskmaster task it relates to is marked done" and "any new gotcha worth remembering is captured in KNOWN_GOTCHAS.md or via /learn".

### Why this matters
The 19 high-confidence learnings on remax-hub-portal sit in `docs/vibe-kit/reference/gstack-learnings.md`. Without explicit instructions, Claude might glance at CLAUDE.md and skip the file. With explicit imperative + "quote the entry key when applying it" expectation, Claude actually loads + uses the institutional knowledge. Same logic for Taskmaster.

### Migration
Re-run `vibe-retrofit tier 2` (or tier 3) on any retrofitted repo. The block hash will change, idempotent merge replaces the old block with the new one (or refuses if you've edited inside it — use `--force` if so).

## [0.1.0-pre.6] — 2026-05-18 (jq -r in learnings rendering)

Caught inspecting the canary's `gstack-learnings.md` after Tier 2 succeeded end-to-end.

### Fixed
- **Bug 11: `gstack-learnings.md` content was JSON-quoted instead of markdown.** The jq invocation in `_scaffold_gstack_reference` was `jq -s ...` not `jq -sr ...` — missing the `-r` raw-output flag. Without it, jq prints each constructed string as a JSON-encoded value (literal `\n` escapes, surrounding quotes), turning 19 confidence-10 institutional-knowledge entries into one-line garbage. Fix: add `-r`.

### Tests
- **Strengthened test 34** with anchored grep (`^## BIG_KEY` instead of substring-only) so a JSON-quoted regression actually fails the test. Plus a `! grep -F '\n'` belt-and-suspenders check.
- The original test passed on the broken output because the assertion only checked substrings. **Lesson logged: assertions on generated docs must be shape-aware or anchored, not just content-substring.**

## [0.1.0-pre.5] — 2026-05-18 (install.sh bash-3.2 var-parse fix)

Caught when re-running install.sh after v0.1.0-pre.4.

### Fixed
- **install.sh: `$SKILL_DIR…` parsed greedily by bash 3.2.** The UTF-8 ellipsis bytes were consumed as part of the variable name. With `set -u`, "unbound variable" fired. Fix: use braced form `${SKILL_DIR}…`. Verified no other `$VAR<non-ascii>` patterns in the codebase.

## [0.1.0-pre.4] — 2026-05-18 (`set -e` traps in scaffolder)

Caught when actually applying Tier 2 to canary on a fresh branch off `origin/main`. The script silently exited mid-`_scaffold_gstack_reference` and never reached `cmd_write_version`, leaving the canary half-retrofitted (no .vibe-kit-version, empty learnings.md, no symlinks).

### Fixed
- **Bug 9: `[ -f x ] && cat x >> y` in the learnings-collection loop killed the script under `set -e`.** Canary has 2 gstack project dirs (current slug + legacy basename) — the legacy one lacks `learnings.jsonl`. That iteration's body returned non-zero, became the loop's exit status, and `set -e` aborted the function. Replaced with an explicit `if [ -f x ]; then cat ...; fi` so the loop body always exits 0.
- **Bug 10: `[ A ] || [ B ] && continue` in the symlink for-loop killed the script even on the success path.** Bash evaluates this as `( [A] || [B] ) && continue`. When neither test fires (count is non-zero — the case we want to proceed), the compound returns false, `set -e` aborts. Replaced with explicit `if ... then continue; fi`.

### Tests
- New regression test (`tier 2: gstack scaffold survives set-e when a legacy project_dir lacks learnings.jsonl`) — would have caught bug 9 + 10. The original test 34 only covered the single-project-dir-with-everything case.
- Suite: 37 green.

### Lesson
- `set -e` + idiomatic bash conditionals (`[ X ] && Y`, `[ A ] || [ B ] && C`) are a classic landmine. Inside a loop or function, the compound's exit status becomes the loop/function's, and `set -e` silently kills the parent. **In any script using `set -e`, always use explicit `if/then/fi`** for conditional execution inside loops and functions. The "clever one-liner" forms are a trap.

## [0.1.0-pre.3] — 2026-05-18 (version-sync + empty-command fallback)

Caught by Tier 2 dry-run on canary before applying.

### Fixed
- **`VIBE_KIT_VERSION` was hardcoded in the script** as `0.1.0-pre`, so every release-version bump required updating both the `VERSION` file AND the script — and the script's value got stale silently. Now sourced from `VERSION` at script startup. Single source of truth. (canary bug 6)
- **Empty inferred commands rendered as literal `` `` `` in CLAUDE.md** (e.g., `Tests: ``) when `package.json` doesn't have a matching script. `jq`'s `//` operator only fires on `null`, not empty strings. Fixed with explicit `if . == null or . == ""` check. Now renders as `Tests: `(not detected — fill in)` ` which is the clear-action signal the template intended. (canary bug 8)

### Known issues (deferred)
- Bug 7: `--dry-run` still writes `.vibe-kit-discovery.{md,json}` because `discover` runs as a sub-step and doesn't honor the parent's dry-run flag. Philosophically wrong but the files are gitignored + idempotent. Defer to v0.2.0 alongside cross-machine work.

### Tests
- 1 new regression test for VERSION sync (asserts script-output version matches `cat VERSION`).
- 1 new regression test for empty-command fallback (asserts `Typecheck:` line in CLAUDE.md doesn't contain literal empty backticks AND does contain "not detected").
- Existing test 22 updated to use dynamic version expectation (was hardcoded as `"0.1.0-pre"`, now reads VERSION at runtime).
- Suite: 36 green.

## [0.1.0-pre.2] — 2026-05-18 (gstack history surfacing)

Second canary iteration. User flagged a major omission: `discover` was only scanning the current repo's tracked files, missing the **94 gstack artifacts** stored at `~/.gstack/projects/<slug>/` for the canary (design docs from `/office-hours`, CEO plans, eng-review test plans, checkpoints, handoff notes, structured learnings, session timeline, deploys log). These are the user's most load-bearing scattered context and skipping them defeats the retrofit's centralizing premise.

### Added
- **`gstack` field in discovery JSON.** Resolves both the current slug (via `~/.claude/skills/gstack/bin/gstack-slug`, which parses `git remote get-url origin` into `owner-repo`) and the legacy basename slug (older gstack versions stored under just the repo name). Catalogs files by type (designs, test_plans, ceo_plans, checkpoints, handoffs, autoplans) and counts JSONL artifacts (reviews, learnings, timeline, deploys). All paths are absolute so downstream consumers can symlink or read directly.
- **"gstack history" section in the markdown discovery report.** Lists slug(s) checked, project dirs found, counts by artifact type, and sample paths (newest 5 designs, newest 5 CEO plans, newest 3 handoffs). User reads this before deciding tier.
- **`_scaffold_gstack_reference` helper, invoked by Tier 2+.** Creates `docs/vibe-kit/reference/` containing:
  - `README.md` explaining the layout + symlink caveat
  - `gstack-learnings.md` — formatted from all `learnings.jsonl` entries across discovered project dirs, deduped by `key` (highest confidence wins on collision), sorted by confidence desc
  - `gstack-designs/`, `gstack-ceo-plans/`, `gstack-checkpoints/`, `gstack-handoffs/`, `gstack-autoplans/`, `gstack-test-plans/` — absolute symlinks to source files
- **`GSTACK_HOME` env var override** (already conventional in gstack itself). Lets tests + future cross-machine workflows point discover at non-default gstack roots.
- **Stdout summary row for gstack.** When artifacts found, summary shows total artifact count + learnings/timeline/deploys counts inline.
- 2 new bats tests (`discover: gstack history surfaces under custom GSTACK_HOME`, `tier 2: scaffold-gstack-reference creates symlinks + gstack-learnings.md`) + 1 new fixture (`with-gstack-history/`). Suite at 35 green.

### Caveats
- Symlinks use absolute paths. They will break on another machine. Re-run `vibe-retrofit tier 2` per-machine to regenerate. Documented in the auto-generated `docs/vibe-kit/reference/README.md`.
- Cross-machine `gstack` artifact aggregation (e.g., scanning a Syncthing-synced folder from another machine) is deferred to a future release. Workaround: set `GSTACK_HOME` to a unified directory if you're already syncing one.

## [0.1.0-pre.1] — 2026-05-18 (canary fixes)

Day-1 dogfooding on first canary repo (`myi1/remax-hub-portal`) surfaced five real bugs in `discover` that the bats fixtures didn't catch. All fixed + new regression tests added.

### Fixed
- **Nested `package.json` detection.** Previously only checked repo root. Now uses `git ls-files` to find any manifest under `apps/*`, `packages/*`, or elsewhere (excludes `node_modules`, `vendor`, `.venv`). Prioritizes `apps/` over `packages/` over deeper paths. Discovered commands get a `(cd <dir> && ...)` prefix when the manifest isn't at repo root, so the CLAUDE.md template renders correct invocations. Same logic applied to `requirements.txt`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Gemfile`. (canary bug 1)
- **TODO file globs broader.** Added `.html`, `.htm`, `.erb`, `.vue`, `.svelte`, `.astro`, `.cs`. Catches TODOs in template files and legacy/migration code. (canary bug 2)
- **Process-doc heuristic for agent files.** Capitalized root-level `.md` files that aren't standard project docs (README/CHANGELOG/LICENSE/CONTRIBUTING/CODE_OF_CONDUCT/SECURITY/AUTHORS/MAINTAINERS/NOTICE/INSTALL/SUPPORT/GOVERNANCE/HISTORY/UPGRADE/TROUBLESHOOTING/FAQ/TODO/BACKLOG/WHATS_NEW/RELEASE_NOTES) now get detected as agent-context files. Catches user-authored process docs like `BRAIN.md`, `DECISION_LOG.md`, `TASK_QUEUE.md`, `SOURCE_OF_TRUTH.md`, `ASSUMPTIONS_REGISTER.md`, `QA_CHECKLIST.md`, `REPO_STRUCTURE.md`. (canary bug 4)
- **Stdout summary stray `0`.** `grep -c . || echo 0` printed `0` twice when input was empty (once from grep, once from echo). Replaced with pre-computed counts that default to 0 cleanly. (canary bug 3)
- **Per-match truncation + total cap on TODO list.** Bug 5 surfaced when bug 2's broader globs ran on the canary: 13 TODO matches totalled 12.9 MB because minified HTML files emit one match per giant single-line file. `jq --arg` blew up with `Argument list too long`. Fix: each match is truncated to 200 chars and total stored matches capped to 200 (rest are noise for the human report anyway). (canary bug 5)

### Added
- 4 new bats tests + 3 new fixtures (`monorepo-nested-pkg/`, `with-process-docs/`, `with-huge-line/`). Suite now at 33 green tests (29 prior + 4 regression).

## [0.1.0-pre] — 2026-05-18

Initial public-but-quiet commit. Full launch deferred to week 3-4 after canary + 4-5 real retrofits prove the workflow.

### Added
- `bin/vibe-retrofit` library with subcommands: `discover`, `merge-claude-md`, `write-version`, `init-taskmaster`, `rollback`, `doctor`, plus `--dry-run` flag on all mutating ops
- `bin/install.sh` for absolute-path wrapper installation to `~/.local/bin/` + skill registration into `~/.claude/skills/vibe-retrofit/`
- `skill/SKILL.md` gstack-style orchestrator skill for fuzzy classification (CLAUDE.md content bucketing, plan-doc triage, synthetic PRD authoring for Taskmaster)
- `templates/CLAUDE.md.tmpl` with variables `{{project_name}}`, `{{primary_language}}`, `{{test_command}}`, `{{typecheck_command}}`, `{{dev_server_command}}`
- `templates/KNOWN_GOTCHAS.md.tmpl` (also serves as the "bug caught by gate" log)
- `templates/docs/vibe-kit/` TODO scaffolds: `PROJECT_MAP.md.tmpl`, `ARCHITECTURE.md.tmpl`, `TESTING.md.tmpl`, `RETROS.md.tmpl`
- `rules/context7.md`, `rules/taskmaster.md`, `rules/verification-checklist.md` — drop-in CLAUDE.md sections
- `sop/SESSION_RITUAL.md` — the one-page session ritual
- `test/retrofit.bats` + `test/handoff.bats` + 8 fixtures (`empty-repo`, `with-claude-md`, `with-claude-md-retrofitted`, `with-todos`, `with-package-json`, `with-existing-plans`, `dirty-tree`, `monorepo`)
- GitHub Actions: `ci.yml` (bats matrix on macOS + Linux), `release.yml` (auto-create GitHub Release on `v*` tag push)

### Design decisions (documented but not yet exercised on a real repo)
- Hybrid architecture: skill orchestrates fuzzy work; bash library handles deterministic ops
- File-based handoff between skill and bash (`.vibe-kit-discovery.json` + `.vibe-kit-classification.json`)
- Idempotency via HTML-comment delimited marker block + per-file template hashes + per-block content hash (`claude_md_block_hash`) — refuses to overwrite user edits inside the block
- Default tier for rescue use case is Tier 3
- `docs/vibe-kit/` namespace (not `docs/agent/`) to avoid collision with agent SDKs
- Always commits to `vibe-kit-retrofit` branch for review + clean revert
- `git grep` (respects `.gitignore`) instead of `grep -r` to avoid `node_modules/.venv/dist/` noise
- Cross-platform sha256 via `_sha256()` helper (shasum on macOS, sha256sum on Linux)

### Known open risks
- Taskmaster `parse-prd` quality on raw discovered TODOs validated on a 5-TODO sample (Day 0 spike, 2026-05-18) — output was clean, $0.0005 cost. Larger inputs (200+ TODOs) not yet exercised.
- Skill classification quality not test-covered (interactive review gate is the mitigation)
