# Research: minordomo-99e — Branch-Conditional Cron Trigger

## Issue

GH #370: Add a condition on the majordomo Jenkinsfile cron so that it only applies for the main branch.

## Current State

`majordomo/Jenkinsfile` has a cron trigger with no branch guard:

```groovy
triggers {
    cron('H/30 * * * 1-5')
}
```

This fires on every branch where the pipeline runs. In a multibranch pipeline setup, the cron would trigger on feature branches and task branches, causing unintended Majordomo runs on non-main branches.

## Solution

Jenkins Declarative Pipeline supports Groovy expressions inside `triggers` block function arguments. The standard idiom to gate a cron on `main` only is:

```groovy
triggers {
    cron(env.BRANCH_NAME == 'main' ? 'H/30 * * * 1-5' : '')
}
```

- When `BRANCH_NAME == 'main'`, the cron schedule is set as before.
- When `BRANCH_NAME` is anything else, the empty string disables the cron.
- `BRANCH_NAME` is set automatically by Jenkins in Multibranch Pipeline jobs.

## Related Files

- `majordomo/Jenkinsfile` — the only file that needs to change
- `minordomo-sweep/Jenkinsfile` — also has a cron trigger but is not mentioned in the issue; left as-is
- `shared/config.yaml` — defines `base_branch: main` (informational; not used in the Jenkinsfile triggers block)

## Scope

Single-file, single-line change. No tests added (Jenkinsfile changes are not covered by the bats test suite). No behavior change for main branch runs.
