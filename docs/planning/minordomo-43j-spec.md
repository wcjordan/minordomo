# minordomo-43j: Fix interactive mode TTY — replace tmux with `script`

## Background

Running a worker with `INTERACTIVE_MODE=true` fails immediately:

```
open terminal failed: not a terminal
```

Jenkins `sh` steps run without a controlling terminal. `tmux new-session -- cmd` (synchronous,
non-detached) requires a controlling terminal to open its session UI — and fails in this context.

The fix: replace tmux with `script -q -e -c "claude ..." /dev/null`. The `script` utility
allocates a pseudo-TTY (PTY) itself without requiring an existing terminal, runs the given
command within it, and propagates the child's exit code with `-e`.

---

## Stage 1: Replace tmux with `script` in interactive worker invocation

### Description

In `shared/agent-pipeline.Jenkinsfile`, change the interactive worker invocation from:

```bash
tmux new-session -- claude --system-prompt-file /tmp/system-prompt.md || CLAUDE_EXIT=$?
```

to:

```bash
script -q -e -c "claude --system-prompt-file /tmp/system-prompt.md" /dev/null || CLAUDE_EXIT=$?
```

Also update the `booleanParam` description on the `INTERACTIVE_MODE` parameter to remove
the stale "via tmux" reference (change to: `'Run worker interactively (worker stage only)'`).

No other files need changing. The Stop hook, `asyncRewake`, transcript-based log analysis, and
all other interactive-mode machinery remain intact.

### Acceptance Criteria

- `shared/agent-pipeline.Jenkinsfile` no longer references `tmux`.
- The `booleanParam` description for `INTERACTIVE_MODE` no longer mentions tmux.
- `make test` passes (shellcheck + bats).
- The interactive worker path invokes `script -q -e -c "claude ..."` and propagates Claude's exit code.
