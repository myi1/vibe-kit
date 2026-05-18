# with-process-docs fixture

This fixture has standard project docs (README, CHANGELOG, LICENSE) AND non-standard process docs (BRAIN.md, DECISION_LOG.md, TASK_QUEUE.md). The bats test asserts that discover picks up the process docs as agent-context files but NOT the standard ones (which are excluded by the heuristic).
