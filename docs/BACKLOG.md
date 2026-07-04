# MacStats Backlog

This backlog is for committed, actionable improvements to MacStats: correctness fixes, reliability or performance work, focused usability improvements, maintainability tasks, and test coverage that keeps the lightweight menu bar app accurate and low overhead.

Completed items should move to `BACKLOG_ARCHIVE.md` with the completion date, a short summary of what changed, and the verification used. Typical verification for this Swift/Xcode project includes `make dev`, `make build`, targeted Xcode builds, and manual menu bar workflows such as checking CPU, Memory, Disk display, settings persistence, and Activity Monitor integration.

Priority meanings:

- `P0`: correctness, data loss, security/privacy, crashes, broken core workflows
- `P1`: important usability, reliability, maintainability, performance, missing tests
- `P2`: polish, cleanup, documentation, nice-to-have improvements

## Priority Tasks

No committed tasks are currently pending.

Backlog items should use this format:

```markdown
### P1 - Task title

- Area: Affected file, module, feature, or behavior.
- Evidence: What shows this is a real issue or useful improvement.
- Acceptance criteria:
  - Concrete condition that must be true when complete.
  - Include tests, docs, or manual checks when appropriate.
- Verification: Build, test, lint, or manual workflow that should prove the task is done.
```