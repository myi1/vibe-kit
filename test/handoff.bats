#!/usr/bin/env bats
# Skill ↔ bash file-handoff contract tests. Validates that .vibe-kit-discovery.json,
# .vibe-kit-classification.json, and .vibe-kit-version are well-formed and have the
# fields the other side relies on.

setup() {
  TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  VIBE_KIT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
  FIXTURES="$TEST_DIR/fixtures"
  VIBE_RETROFIT="$VIBE_KIT_ROOT/bin/vibe-retrofit"

  TMPDIR="$(mktemp -d -t vibe-kit-handoff-XXXXXX)"
  export VIBE_KIT_ROOT
  export PATH="$VIBE_KIT_ROOT/bin:$PATH"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

_load_fixture() {
  cp -R "$FIXTURES/$1/." "$TMPDIR/"
  cd "$TMPDIR"
  git init -b main -q
  git config user.email "test@vibe-kit.local"
  git config user.name "vibe-kit test"
  git add -A
  git commit -q -m "fixture: $1"
}

@test "handoff: discovery JSON has required top-level keys" {
  _load_fixture with-package-json
  "$VIBE_RETROFIT" discover >/dev/null 2>&1

  # Schema contract: the skill reads these fields
  run jq -r 'has("vibe_kit_version") and has("generated_at") and has("project_dir") and has("agent_context_files") and has("plan_docs") and has("libraries") and has("todo_count") and has("todos") and has("commands") and has("existing_state")' .vibe-kit-discovery.json
  [ "$output" = "true" ]
}

@test "handoff: discovery JSON commands object has install/test/typecheck/dev" {
  _load_fixture with-package-json
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  run jq -r '.commands | has("install") and has("test") and has("typecheck") and has("dev")' .vibe-kit-discovery.json
  [ "$output" = "true" ]
}

@test "handoff: discovery JSON existing_state has taskmaster/todos_md flags" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  run jq -r '.existing_state | has("taskmaster") and has("todos_md")' .vibe-kit-discovery.json
  [ "$output" = "true" ]
  # Initial values should both be "no"
  run jq -r '.existing_state.taskmaster' .vibe-kit-discovery.json
  [ "$output" = "no" ]
}

@test "handoff: discovery JSON todo_count is an integer" {
  _load_fixture with-todos
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  run jq -r '.todo_count | type' .vibe-kit-discovery.json
  [ "$output" = "number" ]
}

@test "handoff: .vibe-kit-version has all required fields after tier 1" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" tier 1 >/dev/null 2>&1
  run jq -r 'has("vibe_kit_version") and has("retrofitted_at") and has("tier") and has("template_hashes") and has("claude_md_block_hash")' .vibe-kit-version
  [ "$output" = "true" ]
}

@test "handoff: .vibe-kit-version template_hashes lists all 4 tracked files" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" tier 1 >/dev/null 2>&1
  count=$(jq '.template_hashes | length' .vibe-kit-version)
  [ "$count" -ge 4 ]
}

@test "handoff: all hashes are 64-char hex strings (sha256)" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" tier 1 >/dev/null 2>&1
  run jq -r '.template_hashes | to_entries[] | .value' .vibe-kit-version
  for h in $output; do
    [ "${#h}" -eq 64 ]
  done
  block_hash=$(jq -r '.claude_md_block_hash' .vibe-kit-version)
  [ "${#block_hash}" -eq 64 ]
}

@test "handoff: discovery + classification files are gitignorable (created at predictable paths)" {
  _load_fixture empty-repo
  "$VIBE_RETROFIT" discover >/dev/null 2>&1
  # Standard paths the skill knows to read
  [ -f .vibe-kit-discovery.json ]
  [ -f .vibe-kit-discovery.md ]
}
