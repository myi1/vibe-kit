## Verification gates — when "done" actually means done

Two gates. Apply the right one to the right task.

### Vibe gate (single-file edits, no reversibility cost)

- [ ] Relevant tests pass
- [ ] Typecheck passes
- [ ] No unrelated files changed

That's it. Three checks. Don't skip them because the change "looks fine."

### Spec gate (multi-file, OR touches DB/deploy/shared code/public API)

Everything in the vibe gate, plus:

- [ ] If UI: browser tested, screenshot taken, console clean
- [ ] Diff reviewed (use `/review` for non-trivial diffs)
- [ ] Edge cases listed, remaining risks disclosed
- [ ] Before this change: spec was written (`/office-hours` or `/plan-eng-review` artifact exists)

### Choosing the gate

```
Does this task touch >1 file?
  ├── YES → Spec gate
  └── NO  → Does it have reversibility cost (DB / deploy / shared code / public API)?
              ├── YES → Spec gate
              └── NO  → Vibe gate
```

### When the gate catches a bug

Log it as a one-line entry in this project's `KNOWN_GOTCHAS.md`. The goal is 5+ entries in 4 weeks of use — that's the evidence the gate is doing real work.
