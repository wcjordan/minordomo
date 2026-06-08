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

**`shared/agent-pipeline.Jenkinsfile`**: change the interactive worker invocation from:

```bash
tmux new-session -- claude --system-prompt-file /tmp/system-prompt.md || CLAUDE_EXIT=$?
```

to:

```bash
script -q -e -c "claude --system-prompt-file /tmp/system-prompt.md" /dev/null || CLAUDE_EXIT=$?
```

Also update the `booleanParam` description on the `INTERACTIVE_MODE` parameter to remove
the stale "via tmux" reference (change to: `'Run worker interactively (worker stage only)'`).

**`minordomo-container-builder/Dockerfile`**: two changes:

1. Remove `tmux` from the `apt-get install` package list.

2. After the existing `apt-get` block, add a `RUN` step that verifies `script` (from
   `util-linux`) is at least 2.37 — the version that added `-e`. The `-e` flag is required
   to propagate Claude's exit code to Jenkins. Fail the build if the version check fails:

```dockerfile
# Verify script (util-linux) >= 2.37 for -e (exit-code propagation) support
RUN script --version \
    | awk '/util-linux/{ split($NF, v, "."); if (v[1]+0 > 2 || (v[1]+0 == 2 && v[2]+0 >= 37)) exit 0; exit 1 }' \
    || { echo "ERROR: script (util-linux) >= 2.37 required for -e flag"; exit 1; }
```

The Stop hook, `asyncRewake`, transcript-based log analysis, and all other
interactive-mode machinery remain intact.

### Acceptance Criteria

- `shared/agent-pipeline.Jenkinsfile` no longer references `tmux`.
- The `booleanParam` description for `INTERACTIVE_MODE` no longer mentions tmux.
- `minordomo-container-builder/Dockerfile` no longer installs `tmux`.
- `minordomo-container-builder/Dockerfile` contains a `RUN` step that fails the image build if `script` is older than 2.37.
- `make test` passes (shellcheck + bats).
- The interactive worker path invokes `script -q -e -c "claude ..."` and propagates Claude's exit code.
