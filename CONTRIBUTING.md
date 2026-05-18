# Contributing to vibe-kit

Thanks for the interest. Before you spend time on a PR, please read this.

## Project posture

vibe-kit is a personal-workflow tool that I (the maintainer) use on my own painful AI-coded repos. It is published under MIT because some of what works for me may work for you. **It is not a community project.** Merge cycles are slow. I reserve design authority. Forks are encouraged.

## What kinds of contributions land

Most likely to land:
- Bug fixes with a regression test in `test/retrofit.bats` or `test/handoff.bats`
- Cross-platform shell compatibility fixes (bash 3.2 / Linux / WSL)
- Tightening existing subcommands (idempotency edge cases, error messages, dry-run output)
- Typos, README clarifications, documentation that helps a stranger understand the tool

Possible but slower:
- New fixture under `test/fixtures/` covering a real edge case you hit
- Cross-agent rules generation (`.cursorrules`, `.windsurfrules`, `AGENTS.md`) — already on the v0.2 roadmap, ask first if you want to work on it
- New subcommands that match the design philosophy (interactive, never destructive, file-based handoff with skill)

Unlikely to land without discussion:
- New dependencies (the tool is intentionally bash + jq + git + standard unix)
- Architectural changes (hybrid skill+script is a load-bearing decision)
- "Make it more like X tool" without a specific user pain
- Telemetry, analytics, or any phone-home

## How to file an issue

Use one of the `.github/ISSUE_TEMPLATE/` templates. Include:
- macOS or Linux + version
- bash version (`bash --version`)
- task-master + bats versions
- Exact command run + full output (redact API keys)
- For retrofit issues: the `.vibe-kit-discovery.md` report if you can share it (or a sanitized version)

## How to propose a PR

1. Open an issue first describing the change. Wait for "go ahead" before sinking time.
2. Branch from `main`. Name it `feature/...`, `fix/...`, or `docs/...`.
3. Write or update tests. If the change isn't covered by `test/retrofit.bats` or `test/handoff.bats`, that's the first PR you should send.
4. Run the bats suite locally before pushing: `bats test/`.
5. Keep diffs small. One concern per PR. Don't bundle.
6. Reference the issue in the PR description.

## Running tests

```bash
brew install bats-core   # macOS
# or: npm install -g bats # any OS with node
cd ~/dev/vibe-kit
bats test/
```

CI runs the same suite on macOS + Linux in `.github/workflows/ci.yml`.

## Maintainer

[@myi1](https://github.com/myi1). Solo. Side project. If demand outstrips capacity I'll post a pinned "maintainer wanted" issue rather than burning out silently. PRs not reviewed within 4 weeks are fair to ping once.
