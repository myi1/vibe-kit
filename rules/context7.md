## Context7 — current third-party docs

When implementing against any third-party library, framework, SDK, or API, use the Context7 MCP server to fetch current docs BEFORE writing code. Do not rely on your library memory — library APIs change, and your training data may be stale.

### When Context7 is required

For any code that imports, calls, or configures one of these libraries detected in this project:

{{context7_library_allowlist}}

For any other library not in the list, use Context7 if the API has changed in the last 12 months OR if you are unsure.

### How to use Context7

The Context7 MCP server is configured in `~/.claude.json` and exposes `mcp__context7__*` tools. From a Claude Code session: just reference the library by name; Context7 will return current docs and code examples for the version specified.

### Anti-patterns

- Do NOT write code from memory for libraries in the allowlist above without first checking Context7.
- Do NOT silently fall back to "what the docs probably look like" when Context7 is unavailable. If Context7 is down, say so and pause.
- Do NOT use deprecated APIs from old training data when current docs show the new API.
