# MDOMO-27: Show Prompt Output from Jobs on Jenkins Description

## Overview

Each of the three agent jobs (majordomo, plan, step) runs `claude -p` and emits a JSON
run log to stdout. This feature captures that output and sets it as the Jenkins build
description so operators can see what each run did without opening the full console log.

---

## Stage 1: Show prompt output in Majordomo Jenkinsfile

### Description

Update `majordomo/Jenkinsfile` to capture the stdout of the `claude -p` invocation and
set it as the Jenkins build description. Pipe `claude -p` output through `tee` to write
to `/tmp/prompt-output.txt` while still printing to the console. Add a `post { always
{ script { ... } } }` block at the stage level that reads the file and assigns
`currentBuild.description`. Use `|| true` when reading the file so a missing file (if
claude crashes before producing output) does not fail the post block.

### Acceptance Criteria

- `majordomo/Jenkinsfile` pipes `claude -p` output through `tee /tmp/prompt-output.txt`
- A `post { always { script { ... } } }` block sets `currentBuild.description` from the
  captured file
- The block handles the case where `/tmp/prompt-output.txt` does not exist (uses
  `|| true` or equivalent guard)
- `make test` passes

---

## Stage 2: Show prompt output in Plan and Step Jenkinsfiles

### Description

Apply the same capture-and-describe pattern from Stage 1 to `minordomo-plan/Jenkinsfile`
and `minordomo-step/Jenkinsfile`. Both jobs already follow the same structure as
majordomo: a single `sh` block runs setup scripts plus `claude -p`, followed by nothing
else. Add `| tee /tmp/prompt-output.txt` to the `claude -p` call and a `post { always
{ script { ... } } }` block to each Jenkinsfile.

### Acceptance Criteria

- `minordomo-plan/Jenkinsfile` pipes `claude -p` output through `tee /tmp/prompt-output.txt`
  and sets `currentBuild.description` in a `post { always }` block
- `minordomo-step/Jenkinsfile` does the same
- Both files handle the missing-file case with `|| true` or equivalent
- `make test` passes
