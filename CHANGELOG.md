# Changelog

All notable changes to vibe-kit are documented in this file. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

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
