---
name: vibe-bug
description: Report a vibe-kit bug. Closes the loop on real-world misfires by drafting a structured report and either auto-filing as a GitHub issue (if user opted in via `vibe-retrofit bug-report-mode on`) or saving locally for later upload. Use when another vibe-kit skill or hook misbehaves OR when the user types `/vibe-bug`, "report this bug", "this skill is broken", or "something's wrong with vibe-kit". DO NOT use for: user errors (missing API key, dirty working tree), network failures, expected refusals, or fuzzy "could work better" suggestions — only confirmed vibe-kit defects.
---

# /vibe-bug — close the loop on vibe-kit defects

vibe-kit's quality improves only if real-world misfires reach the maintainer instead of getting silently worked around. This skill is the reporting path.

## Two ways to be invoked

1. **Programmatic** — another vibe-kit skill detects a bug, invokes `/vibe-bug` via the Skill tool, passes the trigger context as input.
2. **User-triggered** — user types `/vibe-bug`, "report this bug", "vibe-kit is broken", etc. Ask the user what happened.

## Hard rule on what counts as a vibe-kit bug

**File a report ONLY when one of these is true:**

- A vibe-kit-provided bash primitive (`vibe-retrofit X`) returned non-zero AND emitted malformed JSON when `--json` was requested
- A vibe-kit-provided hook script emitted JSON that failed to parse OR contained obvious garbage (numeric field that's `"00"`, missing required field, etc.)
- A documented vibe-kit command, file path, or skill referenced in another vibe-kit artifact doesn't exist
- A skill flow left the user in a partially-broken state (mid-migration crash, half-written files, etc.) despite all documented preconditions being met
- A skill couldn't make progress despite ALL preconditions met (not just "Claude got confused")

**DO NOT file** when:

- User had no API key set
- User's repo has uncommitted changes (expected refusal — vibe-kit gates on clean tree)
- Network failure (gh API, gbrain HTTP, etc.)
- User cancelled mid-flow
- Optional dependency (gbrain, task-master) not installed — skill is supposed to skip cleanly
- The skill behaved as documented but the documentation was the surprise (that's a docs issue, not a bug — different report shape, defer for now)
- Anything fuzzier than "thing said X, X demonstrably didn't work"

When unsure, **err toward not filing**. The user can always invoke /vibe-bug explicitly if they think it's worth a report.

## Phase 1 — Build the envelope

Construct the JSON envelope. Schema (matches `docs/design/batch-and-relay-protocol.md` schema_version: 1 style):

```json
{
  "schema_version": 1,
  "skill": "<vibe-retrofit | vibe-start | vibe-wrap | vibe-upgrade | n/a>",
  "vibe_kit_version": "<from `vibe-retrofit version`>",
  "trigger_class": "<malformed_json | missing_command | hook_garbage_output | doc_code_drift | partial_state | no_progress | other>",
  "severity": "<low | medium | high | blocker>",
  "title": "[skill: <X>] <brief verb-led description, < 80 chars>",
  "what_happened": "<2-4 sentences, plain English, no jargon>",
  "expected": "<what should have happened per docs/skill instructions>",
  "actual": "<what actually happened>",
  "reproducer": "<minimal steps a maintainer can follow>",
  "suggested_fix": null | {"file": "path/in/repo", "line": N, "diff": "..."},
  "env": {
    "os": "<uname -srm>",
    "shell": "<bash --version | head -1>",
    "vibe_kit_v": "<from VERSION>",
    "task_master": "<task-master --version 2>/dev/null || 'not installed'>",
    "gbrain": "<gbrain --version 2>/dev/null || 'not installed'>"
  },
  "tool_calls_tail": ["<last 5 relevant tool calls, redacted>"],
  "fingerprint": "<sha8 of trigger_class:skill:title — for dedup>"
}
```

### Severity rubric
- `blocker` — user can't proceed at all; vibe-kit is broken in a way that breaks their workflow
- `high` — affected the current task; user had to work around it
- `medium` — quality issue; nudge/output was wrong but recoverable
- `low` — cosmetic; wrong message, wrong formatting, but functionally fine

### Fingerprint construction (for dedup)

```bash
echo -n "${trigger_class}:${skill}:${title}" | shasum -a 256 | cut -c1-8
```

The CLI's dedup logic skips refiling if the same fingerprint was filed in the last 7 days.

### Suggested fix (optional, file-aware)

Include ONLY when you can:
- Name the exact file:line in the vibe-kit repo (`hooks/X.sh:42`, `bin/vibe-retrofit:118`, etc.)
- Write a 1-10 line diff that's mechanical (regex fix, missing field, etc.)
- Be reasonably confident it doesn't break unrelated code (read surrounding lines first)

If any of those is iffy: set `suggested_fix: null`. Don't guess.

## Phase 2 — Redaction (handled by CLI but verify pre-submission)

The CLI applies redaction automatically (`$HOME` → `~`, strip git remote URLs), but you should also:

- Cap `tool_calls_tail` at 5 entries
- Strip API keys / tokens from any tool_input that's included
- Don't include the full session transcript — just relevant calls leading to the failure
- Strip filesystem paths to `~`-relative form before writing the envelope

## Phase 3 — Write envelope to disk + hand off to CLI

```bash
tmp=$(mktemp)
cat > "$tmp" <<'JSON'
<the envelope built in Phase 1>
JSON
vibe-retrofit bug-report --json "$tmp"
rm -f "$tmp"
```

The CLI handles:
- Local save under `~/.vibe-kit/bug-reports/<ts>.json`
- 7-day dedup check by fingerprint
- If `bug-report-mode on`: file via `gh issue create` OR fall back to pre-filled URL
- If `bug-report-mode off`: local only, prints "uploaded manually via `--upstream`" hint

## Phase 4 — Report back

After CLI returns, tell the user one of these (based on CLI's output):

| CLI output | Message |
|---|---|
| `Filed: <url>` | "Filed at \<url\>. Saved locally too." |
| Dedup hit | "Same fingerprint reported recently; saved locally without refiling to avoid noise." |
| Mode-off save | "Logged locally at \<path\>. To enable auto-filing: `vibe-retrofit bug-report-mode on`. To upload this one: `vibe-retrofit bug-report --upstream <ts>`." |
| URL fallback | "`gh` not authed; copy this URL to file in browser: \<url\>" |

Then RETURN to whatever skill called /vibe-bug. /vibe-bug is a side-effect; don't let it interrupt the user's actual task.

## Phase 5 — When invoked from a user prompt (not from another skill)

If the user typed `/vibe-bug` directly (no caller context), ask:

> "Which vibe-kit skill or hook misbehaved? Brief description of what you saw vs what you expected — I'll draft a report and either auto-file (if you opted in) or save locally."

Then proceed with Phase 1.

## Edge cases

- **vibe-retrofit version unknown** — CLI not installed? Then how did /vibe-bug get invoked? Use `"unknown"`. Probably indicates a deeper problem.
- **`gh` not installed** — CLI handles via URL fallback. Don't error.
- **`~/.vibe-kit/bug-reports/` not writable** — log to stderr, ask user to fix perms, don't crash.
- **User explicitly says "don't file this"** — respect it. Don't run /vibe-bug.

## Completion

- **DONE** — envelope built, CLI invoked, user told the outcome.
- **DONE_LOCAL_ONLY** — saved locally (mode=off or dedup hit), user told.
- **SKIPPED** — judged the issue doesn't meet the hard-rule criteria; told the user why.
- **BLOCKED** — couldn't build the envelope (missing info, can't determine trigger class). Saved what we had as a draft local file.
