# Changelog

All notable changes to vibe-kit are documented in this file. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

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
