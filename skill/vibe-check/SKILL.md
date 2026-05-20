---
name: vibe-check
description: Pre-implement consistency gate. Validates an intended change against the project constitution, the plan, existing code/decisions, and test coverage BEFORE code gets written. Catches drift early (cheaper than at review). Adapted from GitHub spec-kit's /analyze. NOT a full pre-land review (that's gstack /review). Use when the user types `/vibe-check`, says "check before I build this", "does this violate any rules", "sanity-check this plan", or before starting any non-trivial implementation.
---

# /vibe-check — pre-implement drift gate

The cheapest drift insurance: validate the plan against the invariants BEFORE writing code. Catching "this violates the reconcile-layer rule" at plan time costs one sentence. Catching it at review time costs a rewrite. Catching it in prod costs an incident.

**Scope boundary:** this is NOT `/review` (gstack's pre-land PR review that catches bugs in written code). `/vibe-check` runs BEFORE implementation, validates intent against invariants. Different timing, different job. They compose: `/vibe-check` before you build, `/review` before you land.

## Phase 1 — Gather the inputs

You need three things:

1. **The intended change** — what's about to be built. Either:
   - The user describes it ("I'm about to add OAuth refresh-token rotation")
   - A plan/design doc exists (point at it — gstack design doc, a spec, a GitHub issue)
   - It's implicit in the current session (you've been discussing it)

2. **The constitution** (if present):
   ```bash
   [ -f docs/vibe-kit/CONSTITUTION.md ] && cat docs/vibe-kit/CONSTITUTION.md
   ```
   If no constitution exists, note it — the check still runs against plan completeness + KNOWN_GOTCHAS + gbrain, just without the invariants layer. Suggest `/vibe-constitution` for next time.

3. **Context surfaces:**
   ```bash
   [ -f KNOWN_GOTCHAS.md ] && cat KNOWN_GOTCHAS.md
   ```
   If gbrain is available (`mcp__gbrain__*` tools), search for prior decisions/contradictions touching the same area.

## Phase 2 — Run the four checks

### Check 1 — Constitutional compliance
For each invariant in CONSTITUTION.md, ask: **does the intended change violate it?**
- If yes → **VIOLATION**. Name the invariant, explain the conflict, stop.
- If the change is adjacent to an invariant (touches the same area) → flag for care.

### Check 2 — Plan completeness
Does the plan actually cover the requirement?
- Missing edge cases? Error paths? Rollback?
- Untested assumptions?
- Scope creep (doing more than asked) or scope gaps (doing less)?

### Check 3 — Contradiction with existing decisions
- Does this contradict a prior decision? (Check KNOWN_GOTCHAS, gbrain if available, recent handoffs.)
- Is there a known gotcha in this area that the plan ignores?
- Re-inventing something that already exists?

### Check 4 — Test coverage
- What's the verification story? How will you know it works?
- Anything in the change that's hard to test (and therefore where bugs ship)?
- Does the project's quality bar (from the constitution, if it has one) require a test here?

## Phase 3 — Verdict

Emit one of:

**PASS** — consistent with invariants, plan covers the requirement, no contradictions, test story is clear. One-line summary + go-ahead.

**CONCERNS** — not a violation, but address these first:
```
⚠ CONCERNS before implementing:
  - [completeness] Plan doesn't handle the token-refresh-race case
  - [test] No verification story for the concurrent path
  - [gotcha] KNOWN_GOTCHAS entry "X" applies here — account for it
Proceed after addressing, or tell me to proceed anyway.
```

**VIOLATION** — stop:
```
✗ VIOLATION — this breaks a constitutional invariant:
  Invariant: "all DB writes go through reconcile()"
  Conflict: the plan adds a direct `db.insert` in the OAuth handler
  Options: (a) route through reconcile(), (b) amend the invariant via
           /vibe-constitution if it's genuinely outdated (deliberate decision).
```

## Phase 4 — Hand back

After the verdict, return control. `/vibe-check` is a gate, not a doer — it doesn't implement. On PASS, the user/agent proceeds to build. On CONCERNS, they address then build (or override). On VIOLATION, they fix the plan or amend the invariant.

If the user says "proceed anyway" on a CONCERN: respect it, but note in any resulting handoff that the concern was knowingly accepted (so future-you knows it was a choice, not an oversight).

## When to auto-suggest /vibe-check

Proactively suggest running it (don't force) when:
- The user is about to implement something that touches an area covered by a constitutional invariant
- A plan/design doc was just approved and implementation is next
- The change is non-trivial (multi-file, schema, auth, external integration)

Don't suggest it for: typo fixes, one-line changes, exploration, debugging.

## Posture

- **Fast + cheap.** This is a sanity gate, not a deep audit. Minutes, not a full review.
- **Specific.** "This violates invariant X at the OAuth handler" beats "consider security implications."
- **Doesn't implement.** Gate only. Hands back after the verdict.
- **Constitution-optional.** Works without one (plan + gotchas + gbrain), just weaker. Suggests /vibe-constitution if absent.

## Bug detection (v0.8.0)

If CONSTITUTION.md exists but can't be parsed, gbrain search returns malformed results, or the skill can't determine the intended change despite clear input — invoke `/vibe-bug`. NOT a trigger: no constitution present (expected — check degrades gracefully), user override on a CONCERN. See `skill/vibe-bug/SKILL.md`.

## Completion

- **PASS** — verdict delivered, go-ahead given.
- **CONCERNS** — listed, user deciding whether to address or override.
- **VIOLATION** — named the invariant + conflict + options.
- **DEGRADED** — ran without a constitution (plan + gotchas only); suggested /vibe-constitution.
