# monorepo-nested-pkg fixture

No package.json at root. The actual Next.js app lives under `apps/hub/`.
The bats test asserts that `discover` finds `apps/hub/package.json` via git-ls-files
and picks up its scripts + libraries even when root has nothing.
