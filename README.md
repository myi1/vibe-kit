# vibe-kit

Rescue your messy AI-coded repos. WIP — full README + demo coming after first real retrofits.

A personal-workflow rescue tool for solo developers whose AI-assisted coding has produced scattered context, painful repos, and the same mistakes on repeat. `vibe-kit` retrofits existing repos with a session ritual, Context7 (current third-party docs), Taskmaster (real task tracking), and standardized planning docs — pulling in your existing scattered context instead of leaving it stranded.

## Status

v0.1.0-pre — public-but-quiet. Full launch (and full README) lands week 3-4 after 4-5 real retrofits prove the workflow. Watch this space.

## What it does (one paragraph)

You run `vibe-retrofit tier 3` against an existing repo. It scans for your scattered CLAUDE.md customizations, planning docs in `docs/`/`plans/`/`thoughts/`, TODO/FIXME comments, third-party imports, and inferred test/dev commands. It produces a discovery report you read. Then it merges a standardized `## vibe-kit additions` block into your CLAUDE.md (delimited, idempotent, refuses to overwrite your edits), scaffolds `docs/vibe-kit/` with TODO-style outlines pre-pointed at your existing planning docs, initializes Taskmaster, imports your discovered TODOs as tasks. You triage. From then on, every coding session runs through a clear ritual with a verification gate that prevents the next mess.

## Requirements

- macOS or Linux
- bash 3.2+ (Apple stock works)
- git, jq, shasum or sha256sum (all standard)
- [task-master-ai](https://github.com/eyaltoledano/claude-task-master) (`npm i -g task-master-ai`)
- An LLM API key for task-master Tier 3 imports: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `PERPLEXITY_API_KEY`. Without one, Tier 3 task import fails. Set in your shell before running `vibe-retrofit tier 3`.
- For tests: [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`)

## Install (placeholder)

```bash
git clone https://github.com/myi1/vibe-kit ~/dev/vibe-kit
cd ~/dev/vibe-kit
./bin/install.sh
```

`install.sh` writes wrappers to `~/.local/bin/` and registers the `vibe-retrofit` skill into `~/.claude/skills/`.

## Quickstart (placeholder — real instructions after canary retrofit)

Coming after first real retrofit.

## License

[MIT](LICENSE)
