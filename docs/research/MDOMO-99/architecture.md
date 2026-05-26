# Research: MDOMO-99 — Resolves keyword in PR descriptions

## What the issue asks

GH Issue #160: Change PR descriptions targeting the base branch from using
`Implements: <GH Issue URL>` to `Resolves: <GH Issue URL>` so GitHub auto-closes
the linked issue when the PR is merged.

GitHub recognizes these closing keywords: close, closes, closed, fix, fixes, fixed,
resolve, resolves, resolved. The current `Implements:` keyword is not recognized.

## Where the change is needed

### `majordomo/system-prompt.md` — the only place to change

Line ~440 contains the PR body template used by the `check_story_completion` step
(Step 5 in majordomo) when opening the final feature-branch → base-branch PR:

```
Implements: <GH Issue URL>
```

This must become:

```
Resolves: <GH Issue URL>
```

### Other files examined (no changes needed)

- `minordomo-plan/system-prompt.md` — creates PRs for plan docs targeting feature
  branch; no issue URL in body; not relevant
- `minordomo-step/system-prompt.md` — creates PRs for stage implementations targeting
  feature branch; no issue URL in body; not relevant

## Test impact

- `test/validate-prompts.py` — validates file paths and Jenkins job names in prompts;
  changing `Implements` → `Resolves` does not affect this validation
- `test/bats/` — no bats tests cover the PR body template content
- `make test` should pass after the change with no modifications to tests
