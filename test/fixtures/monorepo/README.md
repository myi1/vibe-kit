# Monorepo fixture

Has a `.gitignore` that excludes `node_modules/`, `.venv/`, `dist/`. The bats test creates files inside those ignored dirs with task-marker comments to prove they are NOT picked up by `vibe-retrofit discover` (which uses git grep).

This README intentionally avoids the literal markers (T-O-D-O, F-I-X-M-E, X-X-X, H-A-C-K) so it doesn't itself match the grep.
