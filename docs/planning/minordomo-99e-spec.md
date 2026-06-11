# Implementation Plan: minordomo-99e

Add a branch condition to the Majordomo Jenkinsfile cron trigger so it only fires on the `main` branch.

## Stage 1: Add branch condition to majordomo cron trigger

### Description

Change the `triggers` block in `majordomo/Jenkinsfile` to use a conditional expression so the cron schedule only activates on the `main` branch. On all other branches (feature branches, task branches, etc.) the cron is disabled.

Current:
```groovy
triggers {
    cron('H/30 * * * 1-5')
}
```

Change to:
```groovy
triggers {
    cron(env.BRANCH_NAME == 'main' ? 'H/30 * * * 1-5' : '')
}
```

This uses the Jenkins-provided `BRANCH_NAME` variable, which is set automatically in Multibranch Pipeline jobs. An empty cron expression disables the trigger on non-main branches.

### Acceptance Criteria

- `majordomo/Jenkinsfile` contains `cron(env.BRANCH_NAME == 'main' ? 'H/30 * * * 1-5' : '')` in the `triggers` block.
- The existing cron schedule string `H/30 * * * 1-5` is preserved unchanged.
- No other files are modified.
- `make test` passes.
