# Implementation Plan: Fix bead ID prefix incorrectly used to derive target repo

## Background

All bead IDs created by Majordomo start with `minordomo-` (because `bd` runs in the
minordomo workspace), but multiple parts of the pipeline try to derive the target GitHub
repo by longest-prefix-matching the bead ID against `config.yaml` repos. This always
resolves to `repo=minordomo`, causing agents processing `gcp-setup`, `chalk`, or
`forester` issues to clone and push to the wrong repo.

The fix: extract the repo from the GH Issue URL already stored in the Story bead's
`description` field (e.g. `GH Issue: https://github.com/wcjordan/gcp-setup/issues/16`).

---

## Stage 1: Add repo name as 3rd output line of get-story-key.sh

### Description

`shared/get-story-key.sh` already extracts the GH Issue URL from the Story bead
description and parses the issue number. This stage extends it to also parse and output
the repository name (the path segment between `github.com/wcjordan/` and `/issues/`) as
a third output line.

The existing `REPO` positional parameter (`$2`) is currently accepted but never used
(marked with `# shellcheck disable=SC2034`). It is made optional (`${2:-}`) so existing
callers continue to work without modification while the new output is available for
callers that want it.

All bats tests for `get-story-key.sh` are updated to assert exactly 3 output lines and
that line 3 is the correct repo name.

### Acceptance Criteria
- `shared/get-story-key.sh` outputs the repo name on stdout line 3 (extracted from the
  GH Issue URL in the Story bead description).
- The `REPO` positional parameter is now optional (`${2:-}`) — passing it does not
  change behaviour; omitting it does not cause a fatal error.
- All existing `get-story-key.bats` tests continue to pass.
- New tests verify line 3 contains the correct repo for each happy-path scenario (e.g.
  URL `https://github.com/wcjordan/gcp-setup/issues/16` → line 3 = `gcp-setup`).
- `make test` passes.

---

## Stage 2: Replace prefix-match repo derivation in setup-workspace.sh and sweep-stale-tasks.sh

### Description

Two shell scripts currently derive the target repo by longest-prefix-matching the bead
ID against `config.yaml` repos. Both are updated to call `get-story-key.sh` and read
all three output lines instead.

**`shared/setup-workspace.sh`**

The prefix-match block (currently the first substantive step) is replaced. Because
`get-story-key.sh` calls `bd show` to look up the Story bead, and beads is already
initialized in the minordomo workspace before `setup-workspace.sh` runs (the container
runs `bd prime` at startup), this call is safe before the target repo is cloned.

The updated ordering becomes:
1. Call `get-story-key.sh "${BEADS_TASK_ID}"` and read three lines: `EPIC_KEY`,
   `GH_ISSUE_NUMBER`, `REPO`.
2. `gh auth setup-git` + git config.
3. `gh repo clone wcjordan/${REPO} ${REPO}` + `cd`.
4. `bd bootstrap` / `bd dolt pull` (beads init inside cloned repo, unchanged).

The existing `get-story-key.sh` call later in the script (which set `EPIC_KEY` and
discarded `GH_ISSUE_NUMBER`) is removed because all three values are already captured in
step 1.

**`shared/sweep-stale-tasks.sh`**

The prefix-match block (Step 3 in the sweep script) is replaced with a call to
`get-story-key.sh "$task_id"` that reads all three output lines. The repo derived from
line 3 is used for the subsequent `gh pr list` call and comment. The redundant second
call to `get-story-key.sh` (line 86, which was passing the prefix-match `$repo`) is
collapsed into the single call above.

### Acceptance Criteria
- `shared/setup-workspace.sh` no longer contains any prefix-match/`config.yaml` repo
  lookup; `REPO` is derived entirely from `get-story-key.sh`.
- `shared/sweep-stale-tasks.sh` no longer contains any prefix-match/`config.yaml` repo
  lookup; `repo` is derived entirely from `get-story-key.sh`.
- The `setup-workspace.bats` test `exports REPO, EPIC_KEY, FEATURE_BRANCH correctly`
  continues to pass (fixture `beads-parent-show.json` has a `minordomo` URL so the
  derived repo is still `minordomo`).
- All `sweep-stale-tasks.bats` tests continue to pass (update mock `bd show` output to
  include the GH URL in the Story bead description if needed).
- `make test` passes.

---

## Stage 3: Replace prefix-match repo derivation in majordomo/system-prompt.md and remove unused REPO param

### Description

Six places in `majordomo/system-prompt.md` tell Majordomo to derive the repo by
prefix-matching the bead ID. All six are updated to use `get-story-key.sh` (which now
outputs repo on line 3) instead.

The six occurrences, identified by their step numbers:
- **Step 4, helper 3** (line ~105): "Use longest-match against config repos (same as
  `shared/setup-workspace.sh`)." → Replace with: call `get-story-key.sh` and read
  REPO from line 3. This consolidates helpers 2 and 3 into one `get-story-key.sh`
  call that reads all three lines.
- **Step 5.1a** (line ~141): Plan bead repo derivation → same approach.
- **Step 6.2a** (line ~199): In-progress Plan bead repo derivation → same approach.
- **Step 8.4a** (line ~263): Ready implementation task repo derivation → same approach.
- **Step 9.2b** (line ~321): Story bead repo derivation → since Step 9.2f already calls
  `get-story-key.sh` for EPIC_KEY, move that call earlier and read all three lines
  (EPIC_KEY, GH_ISSUE_NUMBER, REPO) at once.
- **Step 10.2b** (line ~426): Story bead repo derivation → same treatment as Step 9.2b.

In each case, the updated instruction reads:
```bash
{ read -r EPIC_KEY; read -r GH_ISSUE_NUMBER; read -r REPO; } \
    < <(shared/get-story-key.sh "<beads_task_id>")
```

As a final cleanup in this stage, the now-unused `REPO` positional parameter is removed
from `get-story-key.sh` (the `# shellcheck disable=SC2034` line and the `REPO="${2:-}"` 
assignment are deleted), and `get-story-key.bats` is updated to no longer pass a second
argument in test invocations.

### Acceptance Criteria
- `majordomo/system-prompt.md` contains no reference to deriving repo from a "bead ID
  prefix" or "longest-match against config repos".
- All six occurrences updated to use `get-story-key.sh` line-3 output.
- `shared/get-story-key.sh` no longer accepts or mentions a `REPO` positional argument.
- `test/bats/get-story-key.bats` invocations updated to not pass a second argument.
- `make test` passes.
