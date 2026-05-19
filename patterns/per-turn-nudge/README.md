# Pattern 1 — Per-turn nudge (extracted, parameterized)

Adopt-and-rename version of vibe-kit's PostToolUse + UserPromptSubmit
pair. The vibe-kit-specific paths (`~/.vibe-kit/projects/<key>/`) are
swapped for env-var configurable paths so workspace-memory shops can
drop them in.

See [`../../docs/PATTERNS.md#pattern-1`](../../docs/PATTERNS.md) for
the methodology rationale.

## Files

- [`posttooluse.sh`](posttooluse.sh) — silent file-change logger
- [`userpromptsubmit.sh`](userpromptsubmit.sh) — nudge injector

## Configuration (env vars)

| Var | Default | What |
|---|---|---|
| `NUDGE_STATE_DIR` | `~/.local/state/per-turn-nudge` | Where the change log lives |
| `NUDGE_DISABLE` | unset | Set to `1` to disable (silent no-op) |
| `NUDGE_HINT_TASKMASTER` | `1` if `.taskmaster/` exists in cwd | Surface in-progress task count |
| `NUDGE_HINT_GBRAIN` | `1` if `gbrain` is on PATH | Surface markdown-changed nudge |
| `NUDGE_HINT_CUSTOM_CMD` | unset | Path to a script that emits additional hint lines on stdout |

The `NUDGE_HINT_CUSTOM_CMD` extension point is for stacks with their
own task surface (JP-style `commitments.jsonl`, etc.). The script
gets the list of changed file paths on stdin, one per line. Emit
nudge hint lines on stdout (each starts with `  - ` to match the
list format). Empty stdout = no hint from this source.

Example custom hint script for JP-style setup:

```bash
#!/usr/bin/env bash
# nudge-hint-commitments.sh
WORKSPACE="$HOME/workspace"
[ -f "$WORKSPACE/memory/commitments.jsonl" ] || exit 0
in_progress=$(jq -r 'select(.status=="in-progress")' "$WORKSPACE/memory/commitments.jsonl" | wc -l)
[ "$in_progress" -gt 0 ] && echo "  - Commitments: $in_progress in-progress in workspace/memory/commitments.jsonl"
```

Then export `NUDGE_HINT_CUSTOM_CMD=/path/to/nudge-hint-commitments.sh`.

## Wiring into Claude Code

```bash
# Copy the hook files
mkdir -p ~/.claude/hooks
cp posttooluse.sh ~/.claude/hooks/per-turn-posttooluse.sh
cp userpromptsubmit.sh ~/.claude/hooks/per-turn-userpromptsubmit.sh
chmod +x ~/.claude/hooks/per-turn-*.sh

# Wire into settings.json (use jq for safety)
jq '
  .hooks = (.hooks // {}) |
  .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{
    "matcher": "Write|Edit|MultiEdit|NotebookEdit",
    "hooks": [{"type":"command","command":"'"$HOME"'/.claude/hooks/per-turn-posttooluse.sh"}]
  }]) |
  .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [{
    "matcher": "",
    "hooks": [{"type":"command","command":"'"$HOME"'/.claude/hooks/per-turn-userpromptsubmit.sh"}]
  }])
' ~/.claude/settings.json > /tmp/settings.tmp && mv /tmp/settings.tmp ~/.claude/settings.json
```

## Wiring into OpenClaw / other orchestrators

OpenClaw spawns Claude Code per task, so the hooks above install once
at the Claude Code level and fire for every spawned session.

For a custom orchestrator that doesn't use Claude Code: invoke
`posttooluse.sh` after any file-mutating tool call with stdin
shaped like `{"tool_name":"Write","tool_input":{"file_path":"..."}}`,
and invoke `userpromptsubmit.sh` before forwarding each user turn
to the model (capture stdout, treat its `hookSpecificOutput.additionalContext`
field as text to prepend to the model's input).

## Differences from vibe-kit's reference impl

- No `.vibe-kit-version` detection — runs unconditionally if hooks
  are wired. Use `NUDGE_DISABLE=1` to silence.
- No global config file. Env-only.
- No project_key concept. Single workspace state dir for all repos.
- Hint surfaces are extensible via `NUDGE_HINT_CUSTOM_CMD` instead of
  hardcoded gbrain + taskmaster.
