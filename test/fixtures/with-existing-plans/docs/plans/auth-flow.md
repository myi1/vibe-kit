# Auth flow refactor

**Status:** WIP — started 2026-04

## Current state

The auth flow lives in `src/auth/` and has three entry points: login, refresh, logout. Token rotation is hand-rolled (see `session.ts`).

## Plan

1. Move refresh-token logic into a middleware
2. Standardize on signed JWTs for session state
3. Migrate cookie-based fallback path away (deprecated since 2026-02)

## Open questions

- Should we rotate signing keys via Vault or env? (Currently env. Vault later.)
- Mobile clients still on the old refresh endpoint. Sunset plan?
