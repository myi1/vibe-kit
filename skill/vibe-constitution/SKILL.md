---
name: vibe-constitution
description: Establish or amend a project's constitution — the non-negotiable invariants an agent must re-validate against at plan, implement, and review time. Adapted from GitHub spec-kit's constitution concept. The invariants layer ABOVE CLAUDE.md (CLAUDE.md is how-to-work; the constitution is what-not-to-violate). Use when the user types `/vibe-constitution`, says "set project principles", "project invariants", "what are the rules for this repo", or "the agent keeps violating X — make it a rule".
---

# /vibe-constitution — the invariants layer

A constitution is the drift anchor. CLAUDE.md drifts (it's guidance); invariants don't (they're law). When an agent re-validates against a small set of hard constraints at every phase, drift has nowhere to hide.

**Where it lives:** `docs/vibe-kit/CONSTITUTION.md` — IN the repo, branch-coupled (like CLAUDE.md and KNOWN_GOTCHAS.md, NOT the global reference layer). A branch might propose changing an invariant; that should show in the diff.

## Phase 1 — Detect state

```bash
[ -f .vibe-kit-version ] || { echo "Not a vibe-kit repo. Run /vibe-retrofit first."; exit 1; }
if [ -f docs/vibe-kit/CONSTITUTION.md ]; then
  echo "EXISTING — will propose amendments"
  cat docs/vibe-kit/CONSTITUTION.md
else
  echo "FRESH — will draft from scratch"
fi
```

## Phase 2 — Infer candidates from the codebase (fresh) OR read current (amend)

**Fresh repo:** before asking the user anything, infer invariant CANDIDATES from the code so the Q&A is grounded, not blank. Read the template's prompt block (`templates/CONSTITUTION.md.tmpl`) for what each category covers, then scan:

- **Architectural** — directory structure, existing abstractions, ARCHITECTURE.md if present, the CLAUDE.md "do not" section
- **Quality** — CI config (`.github/workflows/`), test setup, `package.json` scripts, any `verify`/`check` commands
- **Security** — `.gitignore` patterns (what's deliberately excluded), any auth/secrets handling, env var usage
- **Data** — migration dirs, schema files, ORM config
- **Process** — branch protection, CONTRIBUTING.md, release/ship scripts, VERSION-file conventions

**Amend mode:** read the existing constitution, hold it in context, and surface what the current session suggests changing (e.g., the user said "stop doing X" → propose X as a new invariant).

## Phase 3 — Q&A per category

For each of the 5 categories (Architectural / Quality / Security / Data / Process), present your inferred candidates and ask the user to confirm, edit, or add:

> "For **architectural invariants**, I see these candidates from the code:
>   1. <inferred candidate> — <why I think it's a rule>
>   2. <inferred candidate>
> Confirm which are real invariants, edit the wording, or add ones I missed. (Or 'none' if this project has no hard architectural rules.)"

Ask ONE category per turn (or batch 2 closely-related ones). Don't dump all 5 at once.

**For each confirmed invariant, capture three things:**
1. **The rule** — imperative, specific, testable ("all DB writes go through `reconcile()`", not "be careful with the database")
2. **Rationale** — one line on why it exists (so future-you doesn't repeal it without understanding the cost)
3. **Verification** — how an agent or human checks compliance ("grep for direct `db.insert` calls outside reconcile.ts", "CI gate `check-system-of-record.sh`")

## Phase 4 — Draft + approve

Render the template (`templates/CONSTITUTION.md.tmpl`), substituting the `{{SLOT_*}}` sections with the confirmed invariants. Strip the prompt block. Substitute `{{project_name}}` and `{{retrofitted_at}}`.

**Omit empty categories entirely.** A constitution with 4 real invariants beats one with 20 vague ones. If the user has no security invariants beyond the obvious, leave the section out rather than padding.

Show the full draft. Ask:

> "Constitution draft above. Approve, edit any invariant, or drop a category?"

Iterate until approved. Write to `docs/vibe-kit/CONSTITUTION.md`.

## Phase 5 — Amend mode specifics

If amending an existing constitution:
- Show a clear before/after diff of what's changing
- Require explicit confirmation per changed invariant (changing law is a real decision)
- Append an entry to the "Amendment log" section: `- <date>: <what changed> — <why> (by <who>)`
- Never silently drop an existing invariant — surface the removal explicitly

## Phase 6 — Report

Tell the user:
- Path written: `docs/vibe-kit/CONSTITUTION.md`
- N invariants across M categories
- Reminder: the SessionStart hook now surfaces it; `/vibe-check` validates against it before implementation
- If amending: what changed + the amendment-log entry

## Posture

- **Few, hard, testable.** Reject vague invariants. "Be thoughtful about X" is not an invariant. "X must Y, verified by Z" is.
- **Infer first, ask second.** Don't make the user invent invariants from nothing — propose candidates from the code.
- **Branch-coupled.** Lives in-repo. An invariant change shows in the git diff. That's the point.
- **Amendment is deliberate.** Adding is easy; removing/changing requires explicit confirmation + a log entry.

## Bug detection (v0.8.0)

If the template's prompt block is missing/malformed, the `{{SLOT_*}}` substitution leaves literal placeholders in the output, or `docs/vibe-kit/` isn't writable despite the repo being retrofitted — invoke `/vibe-bug` via the Skill tool. NOT a trigger: user has no invariants in a category (omitting is correct), user declines to write a constitution. See `skill/vibe-bug/SKILL.md`.

## Completion

- **DONE** — constitution written/amended, N invariants, path surfaced, /vibe-check pointer given.
- **DONE_MINIMAL** — user confirmed only 1-2 invariants; wrote a lean constitution (this is fine, not a concern).
- **SKIPPED** — user decided the project doesn't need a constitution yet.
- **BLOCKED** — not a vibe-kit repo (told user to /vibe-retrofit first).
