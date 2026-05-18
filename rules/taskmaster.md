## Taskmaster — task tracking

Tasks for this project are tracked in [Taskmaster](https://github.com/eyaltoledano/claude-task-master), not in `TODO:` comments in code, not in scattered Markdown files, not in Claude's memory between sessions.

### Authoritative source

The single source of truth for "what work is pending" is:

```bash
task-master list
task-master next
```

`TODO:` / `FIXME:` / `HACK:` comments in code are breadcrumbs only — they should reference a Taskmaster task ID when the work matters. Comments that don't have a task ID either get one (`task-master add-task --prompt "..."` returns an ID you paste back) or get deleted as cruft.

### Required for Tier 3+ retrofit

vibe-retrofit's Tier 3 calls `task-master parse-prd` to import discovered TODOs as initial tasks. This requires an LLM API key in your shell environment:

- `OPENAI_API_KEY` (recommended — used during vibe-kit Day 0 spike, ~$0.0005 per 5 tasks)
- `ANTHROPIC_API_KEY` (alternative)
- `PERPLEXITY_API_KEY` (alternative)

Set one of these before running `vibe-retrofit tier 3`, or Taskmaster will fail with a clear "API key required" error.

### Daily workflow

```
# At session start
task-master next          # what to work on

# When you finish something
task-master set-status <id> done

# When you discover new work
task-master add-task --prompt "..."

# To see the picture
task-master list
```

See `task-master --help` for the full surface.

### Anti-patterns

- Do NOT add scattered TODOs back to `TODOS.md` once Taskmaster is the source of truth.
- Do NOT leave inline `TODO:` comments without a task ID for any non-trivial work.
- Do NOT use Taskmaster as a graveyard. If you have 200+ stale tasks no one updates, delete the stale ones — a graveyard is worse than no tracker.
