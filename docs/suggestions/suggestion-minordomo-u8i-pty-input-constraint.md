Document that `expect` is not available in the minordomo container image and how PTY input is handled for usage checking.

## Suggested addition to docs/GETTING_AROUND.md or a new shared/README.md section

Under "Container Environment" or similar:

> **PTY interaction:** The minordomo container image does NOT include `expect` or `tcl`.
> Interactive PTY sessions (e.g., for `shared/run-claude.sh` and `shared/fetch-claude-usage.sh`)
> rely on `script(1)` from util-linux (>= 2.37, verified in the Dockerfile). When sending
> input to an interactive process via PTY, the only option is stdin redirection with timing
> delays — `expect`-style pattern matching is not available. Scripts that drive PTY input
> must include a hard timeout (e.g., 30s) to avoid hanging builds.

**Target document:** `docs/GETTING_AROUND.md` (container environment section), or add to
`minordomo-container-builder/Dockerfile` as a comment near the `script` verification step.
