# Session Ritual

Read this before every coding session for the first week of adoption. After that, every Monday morning. The point is muscle memory, not a checklist you skim.

## Before starting (5 min)

1. **Open Taskmaster — pick the next task.**
   ```
   task-master next
   ```
   If this project isn't yet on Taskmaster, that means it needs a Tier 3 retrofit. Do that first. Stop reading this file until the retrofit is done.

2. **Decide which gate applies to this task.**
   - Touches >1 file OR has reversibility cost (DB / deploy / shared code / public API)? → **Spec mode**
   - Single file, no reversibility cost? → **Vibe mode**

3. **If Spec mode**: run `/office-hours` or `/plan-eng-review` BEFORE coding. The artifact becomes the source of truth — Claude reads it, you reference it, the review gate uses it.

## During (every task)

1. **Prompt structure**: Goal / Context / Constraints / Done-when — written out, not implied. "Just fix it" is not a prompt.
2. **Third-party library?** Context7 first. Never trust Claude's library memory. (See `rules/context7.md`.)
3. **Edit minimally.** No surrounding cleanup. No "while I'm here" refactors. If you see real cruft, capture it as a Taskmaster task.
4. **Run checks yourself.** Typecheck + relevant tests. "Should work" is not a signal.

## Before declaring done (apply the gate)

### Vibe gate
- [ ] Relevant tests pass
- [ ] Typecheck passes
- [ ] No unrelated files changed

### Spec gate (everything in Vibe gate, plus:)
- [ ] If UI: browser tested, screenshot taken, console clean
- [ ] Diff reviewed (use `/review`)
- [ ] Edge cases listed, remaining risks disclosed

## End of session

- `/context-save` before closing the laptop.
- Corrected Claude twice on the same thing? Run `/learn` to capture it.
- Bug that the gate caught? One-line entry in this project's `KNOWN_GOTCHAS.md`. Count them at week 4 — goal is 5+.

## Weekly (Friday)

- `/retro` on the week.
- Prune `KNOWN_GOTCHAS.md` of duplicates.
- Anything you've corrected 3+ times → candidate for promotion into the `vibe-kit` template itself (Earned Additions rule).

## Anti-patterns this ritual prevents

- "It looked fine" → caught by the gates
- "I'll add a test later" → blocked at vibe-gate step 1
- "Claude usually gets this right" → forced to verify yourself
- "I'll remember what I changed" → /context-save creates the receipt
- "I corrected this last week" → captured by /learn so you don't relearn it
- Scattered TODOs across files → Taskmaster is the source of truth
- Library API I'm not sure about → Context7 first

The ritual is the design. If you stop reading it, the design failed.
