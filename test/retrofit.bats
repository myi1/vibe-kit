#!/usr/bin/env bats
# Integration tests for vibe-retrofit. Each test spins up a temp git repo from
# a fixture under test/fixtures/, runs vibe-retrofit, asserts on output state.

setup() {
  # Resolve paths relative to this test file.
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  VIBE_KIT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
  VIBE_RETROFIT="$VIBE_KIT_ROOT/bin/vibe-retrofit"

  # Make sure the binary is executable
  [ -x "$VIBE_RETROFIT" ] || chmod +x "$VIBE_RETROFIT"

  # Each test runs in a fresh tmpdir
  TMPDIR="$(mktemp -d -t vibe-kit-test-XXXXXX)"
  export VIBE_KIT_ROOT
  export PATH="$VIBE_KIT_ROOT/bin:$PATH"
}

teardown() {
  if [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ]; then
    rm -rf "$TMPDIR"
  fi
}

# Helper: copy a fixture into TMPDIR, init git, commit everything.
_load_fixture() {
  local name="$1"
  cp -R "$FIXTURES/$name/." "$TMPDIR/"
  cd "$TMPDIR"
  git init -b main -q
  git config user.email "test@vibe-kit.local"
  git config user.name "vibe-kit test"
  # Stage even hidden files like .gitkeep, .gitignore
  git add -A
  git commit -q -m "fixture: $name initial"
}

# ============================================================================
# Discovery tests
# ============================================================================

@test "discover: empty repo produces report with zero counts" {
  _load_fixture empty-repo
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  [ -f .vibe-kit-discovery.md ]
  [ -f .vibe-kit-discovery.json ]
  # JSON counts should all be zero/empty
  run jq '.todo_count' .vibe-kit-discovery.json
  [ "$output" = "0" ]
  run jq '.agent_context_files | length' .vibe-kit-discovery.json
  [ "$output" = "0" ]
}

@test "discover: with-claude-md fixture detects CLAUDE.md as agent file" {
  _load_fixture with-claude-md
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  run jq -r '.agent_context_files[0]' .vibe-kit-discovery.json
  [ "$output" = "CLAUDE.md" ]
}

@test "discover: with-todos fixture finds 7+ TODOs across .ts/.py/.md" {
  _load_fixture with-todos
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  # 3 TODOs in auth.ts (TODO, FIXME, HACK), 3 in billing.py (TODO, FIXME, XXX), 3 in notes.md
  count=$(jq '.todo_count' .vibe-kit-discovery.json)
  [ "$count" -ge 7 ]
}

@test "discover: with-package-json infers npm test/typecheck/dev commands" {
  _load_fixture with-package-json
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  run jq -r '.commands.test' .vibe-kit-discovery.json
  [ "$output" = "vitest run" ]
  run jq -r '.commands.typecheck' .vibe-kit-discovery.json
  [ "$output" = "tsc --noEmit" ]
  run jq -r '.commands.dev' .vibe-kit-discovery.json
  [ "$output" = "next dev" ]
}

@test "discover: with-package-json picks up libraries (next, react, openai, stripe)" {
  _load_fixture with-package-json
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  run jq -r '.libraries[]' .vibe-kit-discovery.json
  [[ "$output" == *"next"* ]]
  [[ "$output" == *"react"* ]]
  [[ "$output" == *"openai"* ]]
  [[ "$output" == *"stripe"* ]]
}

@test "discover: with-existing-plans finds docs/plans/ and thoughts/ files" {
  _load_fixture with-existing-plans
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  run jq -r '.plan_docs[]' .vibe-kit-discovery.json
  [[ "$output" == *"docs/plans/auth-flow.md"* ]]
  [[ "$output" == *"thoughts/2024-q3-refactor.md"* ]]
  [[ "$output" == *"docs/api-conventions.md"* ]]
}

@test "discover: monorepo with .gitignore excludes node_modules TODOs" {
  _load_fixture monorepo
  # Add a node_modules/ dir with a TODO file that should be IGNORED
  mkdir -p node_modules/some-pkg .venv/lib dist
  echo "// TODO: in node_modules — should not appear" > node_modules/some-pkg/index.js
  echo "# TODO: in .venv — should not appear" > .venv/lib/foo.py
  echo "// TODO: in dist — should not appear" > dist/bundle.js

  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  # Only the app-source TODO should appear, not the ignored ones
  count=$(jq '.todo_count' .vibe-kit-discovery.json)
  [ "$count" -eq 1 ]
  run jq -r '.todos[0]' .vibe-kit-discovery.json
  [[ "$output" == *"apps/web/src/index.ts"* ]]
}

# ============================================================================
# Dry-run tests
# ============================================================================

@test "merge-claude-md --dry-run: no files mutated on empty repo" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  run "$VIBE_RETROFIT" merge-claude-md --dry-run
  [ "$status" -eq 0 ]
  # No CLAUDE.md created, no .vibe-kit-version written
  [ ! -f CLAUDE.md ]
  [ ! -f .vibe-kit-version ]
}

@test "tier 1 --dry-run: no mutations on with-claude-md" {
  _load_fixture with-claude-md
  run "$VIBE_RETROFIT" tier 1 --dry-run
  [ "$status" -eq 0 ]
  # No mutation — CLAUDE.md is unchanged
  run git status --porcelain
  # Allow the discovery reports (they're created by discover, gitignored in real use)
  # but no modified tracked files
  [ -z "$(git diff --name-only)" ]
  [ -z "$(git diff --cached --name-only)" ]
}

# ============================================================================
# Idempotency tests
# ============================================================================

@test "merge-claude-md: idempotent on with-claude-md-retrofitted (block hash unchanged)" {
  _load_fixture with-claude-md-retrofitted
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  # Write the version file with the CURRENT block hash so re-merge sees no mismatch
  "$VIBE_RETROFIT" write-version --tier 1 >/dev/null 2>&1
  # Now re-run merge — should succeed because the stored hash matches the current block
  run "$VIBE_RETROFIT" merge-claude-md
  [ "$status" -eq 0 ]
  # Only one marker block should exist
  count=$(grep -c "<!-- vibe-kit-retrofit:v0.1 " CLAUDE.md)
  [ "$count" -eq 1 ]
}

@test "merge-claude-md: refuses when user edited inside marker block (committed)" {
  _load_fixture with-claude-md-retrofitted
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  "$VIBE_RETROFIT" write-version --tier 1 >/dev/null 2>&1
  git add .vibe-kit-version && git commit -q -m "store version" || true

  # User edits inside the block AND commits (otherwise dirty-tree check fires first)
  sed -i.bak 's/Custom edits inside will be overwritten/USER EDITED HERE/' CLAUDE.md
  rm -f CLAUDE.md.bak
  git add CLAUDE.md && git commit -q -m "user edits inside block"

  # merge should refuse with block-hash-mismatch
  run "$VIBE_RETROFIT" merge-claude-md
  [ "$status" -ne 0 ]
  # Match against the hash-mismatch error phrasing
  echo "$output" | grep -qE 'hash mismatch|Block hash|edited the vibe-kit'
}

@test "merge-claude-md --force: overrides block hash mismatch" {
  _load_fixture with-claude-md-retrofitted
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  "$VIBE_RETROFIT" write-version --tier 1 >/dev/null 2>&1
  git add .vibe-kit-version && git commit -q -m "store version" || true

  # User edits inside the block AND commits (else dirty-tree fires first)
  sed -i.bak 's/Custom edits inside/EDITED CUSTOM/' CLAUDE.md
  rm -f CLAUDE.md.bak
  git add CLAUDE.md && git commit -q -m "user edits inside block"

  # --force should succeed
  run "$VIBE_RETROFIT" merge-claude-md --force
  [ "$status" -eq 0 ]
  # The edit is gone, block is regenerated
  run grep "EDITED CUSTOM" CLAUDE.md
  [ "$status" -ne 0 ]
}

# ============================================================================
# Dirty-tree refusal
# ============================================================================

@test "merge-claude-md: refuses on dirty CLAUDE.md" {
  _load_fixture dirty-tree
  # Make CLAUDE.md dirty by appending without committing
  echo "" >> CLAUDE.md
  echo "uncommitted line" >> CLAUDE.md
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  run "$VIBE_RETROFIT" merge-claude-md
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uncommitted"* ]] || [[ "$output" == *"uncommitted"* ]]
}

# ============================================================================
# Tier escalation
# ============================================================================

@test "tier 1: creates CLAUDE.md + .vibe-kit-version on empty repo" {
  _load_fixture empty-repo
  run "$VIBE_RETROFIT" tier 1
  [ "$status" -eq 0 ]
  [ -f CLAUDE.md ]
  [ -f .vibe-kit-version ]
  # JSON is well-formed
  run jq -r '.vibe_kit_version' .vibe-kit-version
  [ "$output" = "0.1.0-pre" ]
  run jq -r '.tier' .vibe-kit-version
  [ "$output" = "1" ]
  # block_hash is populated
  hash=$(jq -r '.claude_md_block_hash' .vibe-kit-version)
  [ ${#hash} -eq 64 ]
}

@test "tier 2: scaffolds docs/vibe-kit/ TODO scaffolds + KNOWN_GOTCHAS.md" {
  _load_fixture with-package-json
  run "$VIBE_RETROFIT" tier 2
  [ "$status" -eq 0 ]
  [ -f docs/vibe-kit/PROJECT_MAP.md ]
  [ -f docs/vibe-kit/ARCHITECTURE.md ]
  [ -f docs/vibe-kit/TESTING.md ]
  [ -f docs/vibe-kit/RETROS.md ]
  [ -f KNOWN_GOTCHAS.md ]
  # tier 2 stamp
  run jq -r '.tier' .vibe-kit-version
  [ "$output" = "2" ]
}

# ============================================================================
# Doctor
# ============================================================================

@test "doctor: reports unretrofitted on plain repo" {
  _load_fixture empty-repo
  run "$VIBE_RETROFIT" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"not retrofitted"* ]]
}

@test "doctor: reports retrofitted after tier 1" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" tier 1 >/dev/null 2>&1
  run "$VIBE_RETROFIT" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"retrofitted"* ]]
  [[ "$output" == *"tier 1"* ]]
}

# ============================================================================
# Version + help
# ============================================================================

@test "version: prints version string" {
  run "$VIBE_RETROFIT" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"vibe-retrofit"* ]]
  [[ "$output" == *"0.1.0-pre"* ]]
}

@test "help: prints usage" {
  run "$VIBE_RETROFIT" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"discover"* ]]
  [[ "$output" == *"merge-claude-md"* ]]
}

@test "unknown subcommand: fails clearly" {
  cd "$TMPDIR"
  git init -q
  run "$VIBE_RETROFIT" doesnotexist
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown subcommand"* ]]
}

# ============================================================================
# Canary-discovered bugs — regression tests (v0.1.0-pre.1)
# ============================================================================

@test "discover: nested package.json (apps/hub/) — picks up libs + scripts when root has no manifest" {
  _load_fixture monorepo-nested-pkg
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  # Libraries should be populated from apps/hub/package.json
  run jq -r '.libraries[]' .vibe-kit-discovery.json
  [[ "$output" == *"next"* ]]
  [[ "$output" == *"@prisma/client"* ]]
  [[ "$output" == *"next-auth"* ]]
  # Commands should be cd-prefixed since manifest isn't at root
  run jq -r '.commands.dev' .vibe-kit-discovery.json
  [[ "$output" == *"cd apps/hub"* ]]
  [[ "$output" == *"next dev"* ]]
}

@test "discover: capitalized root .md files are detected as process docs (BRAIN.md, DECISION_LOG.md, TASK_QUEUE.md)" {
  _load_fixture with-process-docs
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  # All three process docs picked up
  run jq -r '.agent_context_files[]' .vibe-kit-discovery.json
  [[ "$output" == *"BRAIN.md"* ]]
  [[ "$output" == *"DECISION_LOG.md"* ]]
  [[ "$output" == *"TASK_QUEUE.md"* ]]
  # Standard project docs NOT included
  run jq -r '.agent_context_files | join(" ")' .vibe-kit-discovery.json
  [[ "$output" != *"README.md"* ]]
  [[ "$output" != *"CHANGELOG.md"* ]]
}

@test "discover: truncates per-match lines longer than 200 chars (minified-HTML protection)" {
  _load_fixture with-huge-line
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  # The single TODO is in a 5KB single-line file. After truncation the stored
  # match should be ≤ ~250 chars (200 line + "…[truncated]" marker), not 5K+.
  longest=$(jq -r '.todos[] | length' .vibe-kit-discovery.json | sort -rn | head -1)
  [ "$longest" -le 300 ]
  # And the match content is preserved enough to find the TODO marker
  run jq -r '.todos[0]' .vibe-kit-discovery.json
  [[ "$output" == *"truncated"* ]]
}

@test "discover: stdout summary doesn't print stray '0' when libs is empty" {
  _load_fixture empty-repo
  run "$VIBE_RETROFIT" discover
  [ "$status" -eq 0 ]
  # The summary output should NOT contain a line that is just "0" (the old bug
  # where `grep -c . || echo 0` printed 0 twice).
  ! echo "$output" | grep -E '^[[:space:]]*0[[:space:]]*$'
}

# ============================================================================
# Rollback dry-run
# ============================================================================

@test "rollback --dry-run: enumerates planned cleanup" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" tier 1 >/dev/null 2>&1
  git add -A
  git commit -q -m "vibe-kit-retrofit tier 1" --allow-empty
  run "$VIBE_RETROFIT" rollback --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
}
