# Known gotchas — vibe-kit

vibe-kit itself dogfoods the verification gate (Layer 4 rule: "the kit is its own vibe-kit project"). This file is the log.

## Caught before commit

### 2026-05-18 — first canary retrofit revealed 4 bugs in `discover`

Ran `vibe-retrofit discover` on `~/Documents/GitHub/remax-hub-portal` (canary repo). Caught:

1. **Nested `package.json` not detected.** Canary has `apps/hub-portal/package.json` (monorepo layout). Discover only checked root. Result: blank commands + empty Context7 library list in the rendered CLAUDE.md template — the retrofit would have looked useless.
   - **Fix:** use `git ls-files` to find any manifest, prefer `apps/*`/`packages/*` paths, prefix discovered commands with `(cd <dir> && ...)` when manifest isn't at root.
   - **Regression test:** `test/fixtures/monorepo-nested-pkg/` + 1 bats test.

2. **TODO globs missed `.html`.** Canary has 13 TODOs in `MVP/!old/A2A_Form_Portal*.html` (legacy migration files). Not the user's hot code but real existing context.
   - **Fix:** added `.html`, `.htm`, `.erb`, `.vue`, `.svelte`, `.astro`, `.cs`.

3. **Stdout summary printed `0` on its own line.** Pattern `grep -c . || echo 0` writes `0` twice when input is empty (grep prints `0` because that's its match count; `|| echo 0` also fires because grep exited 1). Cosmetic but visible in the very first thing users see.
   - **Fix:** pre-compute counts, default to `0` cleanly without the OR chain.
   - **Regression test:** asserts the output has no standalone-`0` line on an empty repo.

4. **Process docs at root not detected as agent context.** Canary has 7 capitalized `.md` files at root (`BRAIN.md`, `DECISION_LOG.md`, `TASK_QUEUE.md`, etc.) that ARE the user's existing agent workflow. The hardcoded agent-files list (CLAUDE.md, AGENTS.md, .cursorrules, etc.) missed all of them.
   - **Fix:** added heuristic — any root-level capitalized `.md` that isn't a standard project doc gets included.
   - **Regression test:** `test/fixtures/with-process-docs/` + 1 bats test.

### 2026-05-18 — `set -e` + `[ ... ] && cmd` killed scaffolder silently

When applying Tier 2 to the canary on a fresh branch off main, the script appeared to finish but produced a half-retrofitted state: `docs/vibe-kit/reference/gstack-learnings.md` was empty (just the header), no symlinks were created, and `.vibe-kit-version` wasn't written at all.

Root cause: `set -e` + idiomatic bash conditionals. Two specific patterns killed the script silently:

1. `[ -f "$pd/learnings.jsonl" ] && cat "$pd/learnings.jsonl" >> "$_tmp_jsonl"` inside a while loop. When `[ -f ]` was false (the legacy `remax-hub-portal/` slug dir had no learnings.jsonl), the && short-circuited and the body returned 1. Loop's exit status carried that 1. `set -e` killed the function.

2. `[ "$count" = "0" ] || [ -z "$count" ] && continue` in the symlink for-loop. Bash parses this as `( [A] || [B] ) && continue`. When BOTH tests are false (the success case — count is non-zero!), the compound returns false, `set -e` aborts.

**Fix:** explicit `if/then/fi` for both. The "clever one-liner" forms are a landmine inside `set -e`.

**The bats test didn't catch it** because the original fixture only had ONE project dir, WITH learnings.jsonl present. The failing paths never triggered. Real-world canary had two project dirs, asymmetric content. **Add a "asymmetric" or "missing-file" variant to fixtures wherever code branches on existence checks.**

### 2026-05-18 — major omission: gstack artifacts entirely missing from discover

User flagged it directly during canary review: `~/.gstack/projects/myi1-remax-hub-portal/` has 94 entries (design docs, CEO plans, eng-review test plans, checkpoints, handoffs, structured learnings, session timeline, deploys log) plus an older `~/.gstack/projects/remax-hub-portal/` slug with 6 more. My discover saw zero of them because it only scanned the current repo's tracked files.

This was load-bearing scattered context the retrofit's whole premise is supposed to centralize. Missing it meant the retrofit would have shipped CLAUDE.md + scaffolds without any of the user's real institutional knowledge surfaced.

**Lessons:**
- The retrofit's "scattered context" framing must extend beyond the repo. Personal-workflow tools accumulate state in `~/.tool-name/projects/<slug>/`. Discovery has to know about those locations.
- `gstack-slug` (or whatever the upstream tool uses) is the canonical slug. Re-deriving it elsewhere is wrong — always reuse the source-of-truth resolver. Plus check the basename fallback for legacy slug formats.
- `learnings.jsonl` is the highest-value structured artifact. Formatting it into a readable markdown deduplicates institutional knowledge across sessions. The user's canary had a confidence-10 entry about `TWILIO_DEFAULT_TEAM_ID` convention that a fresh agent would otherwise relearn or violate.

**Fix:** v0.1.0-pre.2 adds gstack scan + reference scaffolding. See CHANGELOG for full detail.

### 2026-05-18 — fix 2 then revealed bug 5 (cascading discovery)

After fixing bugs 1-4 and re-running discover on canary, hit `Argument list too long` from `jq`. Investigation: only 13 TODO matches but 12.9 MB total output — because bug-2's broader globs now include `.html`, and the canary has minified single-line HTML legacy files (each ~1 MB) where one TODO match emits the entire file content.

- **Fix:** truncate each match to 200 chars, cap total stored matches to 200. Anything beyond is noise for the human report and risks blowing argv.
- **Regression test:** `test/fixtures/with-huge-line/` with a 5KB single-line HTML file containing one TODO. Asserts stored match length is ≤ 300 chars and truncation marker is visible.

**Lesson:** the bats fixtures were "ideal-shaped" — they covered the happy paths and obvious edge cases. The canary surfaced shapes I hadn't imagined (monorepo, custom process-doc conventions, single-line minified files). This is exactly why the design said "Day 2-3 canary will catch things fixtures can't."

**Second-order lesson:** fixing one bug can reveal another. Bug 5 was hidden by bug 2 (without the .html glob, the 12.9 MB never materialized). Re-running the canary after each batch of fixes is the gate that catches cascading issues.

## Recurring agent mistakes

(none yet — no /learn entries)

## Project quirks

- Apple stock bash is 3.2.57. The script avoids bash 4+ features (`mapfile`, `${var,,}`, associative arrays, `&>>`).
- awk `-v` doesn't accept multi-line values. The marker-block replace in `merge-claude-md` writes the new block to a tempfile and reads it via `getline` inside awk instead.
- jq is a hard dependency. Without it, discovery falls back to empty libs/commands.
- task-master Tier 3 import requires `OPENAI_API_KEY` (or `ANTHROPIC_API_KEY` / `PERPLEXITY_API_KEY`) — task-master's `add-task` and `parse-prd` both call an LLM. Day 0 verified `parse-prd` works cleanly with `gpt-4o-mini` at ~$0.0001/task.
