# Root Cause: `open terminal failed: not a terminal`

## Error

```
+ tmux new-session -- claude --system-prompt-file /tmp/system-prompt.md
open terminal failed: not a terminal
```

## Root Cause

Jenkins `sh` steps execute commands without a controlling terminal (TTY). Even though the
Kubernetes pod spec has `tty: true` (needed to keep the `cat` process alive), when Jenkins
executes `sh` blocks inside the container via `exec`, the resulting process has no controlling
terminal.

When `tmux new-session -- cmd` runs synchronously (without `-d`), tmux tries to open a terminal
to display its session UI — and fails because there is no controlling terminal.

## Why tmux was used

From `docs/plan/interactive-step-agent-plan.md`:
> tmux provides the TTY that interactive mode requires; running synchronously means the Jenkins
> `sh` step blocks until tmux exits and exit codes propagate naturally.

tmux was the chosen mechanism to give Claude a PTY in a context that doesn't have one.

## Fix

Use `script` from util-linux instead of tmux. `script` allocates a pseudo-TTY (PTY), runs the
given command within it, and — with `-e` — propagates the child's exit code to the caller:

```bash
script -q -e -c "claude --system-prompt-file /tmp/system-prompt.md" /dev/null
```

- `-q` suppresses `Script started` / `Script done` banners
- `-e` returns the exit code of the inner command
- `/dev/null` as the typescript file discards captured PTY output (Claude writes its transcript
  to a JSONL file; we don't need the PTY output separately)

`script` from util-linux 2.37+ supports `-e`. Confirmed available on the planning agent host
at version 2.41.

The Stop hook's `asyncRewake` mechanism is internal to Claude Code and does not interact through
the terminal's stdin — it works regardless of whether tmux or `script` wraps Claude. Removing
tmux has no effect on hook behaviour.

## Affected file

`shared/agent-pipeline.Jenkinsfile` line 77 (the `isInteractiveWorker` branch):
```bash
# before
tmux new-session -- claude --system-prompt-file /tmp/system-prompt.md || CLAUDE_EXIT=$?

# after
script -q -e -c "claude --system-prompt-file /tmp/system-prompt.md" /dev/null || CLAUDE_EXIT=$?
```

Also update the `booleanParam` description on line 11 to remove the stale "via tmux" reference.
