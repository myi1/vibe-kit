---
name: vibe-upgrade
description: Upgrade vibe-kit to the latest version. Checks current vs latest tag on GitHub, shows what changed in CHANGELOG, confirms with you, runs git pull + reinstall. Idempotent — safe to invoke anytime. Use when the user says "upgrade vibe-kit", "update vibe-kit", "vibe-kit upgrade", "/vibe-upgrade", "is vibe-kit out of date", or when the SessionStart hook briefing flagged an outdated version.
---

# /vibe-upgrade — keep vibe-kit current

Thin orchestrator over `vibe-retrofit upgrade`. Surfaces what changed before applying.

## Phase 1 — Check status

```bash
vibe-retrofit upgrade --check --json
```

Parse the JSON. Three outcomes:

- `outdated: false` → tell the user `vibe-kit is at latest ($current)`, stop. No work needed.
- `outdated: true` → continue to Phase 2 with `current` and `latest` versions in hand.
- `error: "fetch_failed"` → tell the user "couldn't reach origin (offline or git issue). Try again later." Stop.

## Phase 2 — Show what changed

Pull the CHANGELOG entries between the current and latest version. This is what the user is signing off on, so it MUST be shown:

```bash
# Extract CHANGELOG section for the latest version only — that's what they're upgrading TO.
# (The user already has the current version's changes; what matters is the diff.)
awk -v target="[$latest]" '
  /^## \[/ {
    if (in_block) exit
    if (index($0, target)) { in_block=1 }
  }
  in_block { print }
' ~/dev/vibe-kit/CHANGELOG.md | head -50
```

Show the user the headline section + the first ~30 lines. If there are multiple versions between current and latest (e.g. current=0.3.0, latest=0.5.0, missed 0.4.0), pull each section and concatenate.

Keep the displayed summary to one viewport. The user is making a "yes/no upgrade" call, not reading the full changelog.

## Phase 3 — Confirm

Use AskUserQuestion:

> "Upgrade vibe-kit `$current` → `$latest`? CHANGELOG above shows what's new."

Options:
- **Upgrade now** (Recommended) — runs the upgrade
- **Cancel** — leave at current version

If the user picks "Cancel," report cancelled + stop.

## Phase 4 — Apply upgrade

```bash
vibe-retrofit upgrade --auto
```

Stream the output to the user. The script handles:
- `git pull --ff-only` (refuses if vibe-kit working tree is dirty)
- `bash bin/install.sh` (refreshes wrapper, skills, hook)
- Reports final version

## Phase 5 — Report

Tell the user:
- ✓ Upgraded `$current` → `$new_version`
- New skills available (if any installed in this upgrade — `ls ~/.claude/skills/` and diff against memory)
- If a CHANGELOG section calls out a "Migration" step the user should take, surface it verbatim

## Edge cases

- **vibe-kit working tree has uncommitted changes:** `git pull --ff-only` fails. Tell the user to `cd ~/dev/vibe-kit && git status` to inspect. They either commit/stash or run `--auto` again after cleaning.
- **install.sh fails mid-way:** vibe-kit may be in a partial state. Tell user to manually run `cd ~/dev/vibe-kit && bash bin/install.sh` and inspect the output.
- **Network unreachable mid-fetch:** the bash script handles this via timeout. If we got past Phase 1, network is fine for the pull too in most cases.
- **Skills directory missing:** `bin/install.sh` recreates it. Should be transparent.

## Posture

- Always show the CHANGELOG diff before applying. Never silent upgrade.
- The bash CLI owns the actual git + install operations. This skill is purely the conversation around them.
- Auto-check at session start is the SessionStart hook's job, not this skill's. This skill is invoked on-demand.

## Completion

Report DONE with: old version, new version, any migration steps the user should take.
Report SKIPPED if already at latest.
Report CANCELLED if user declined.
Report BLOCKED if the upgrade failed mid-way (with paste-ready recovery command).
