# minordomo-24r: Fix datetime.utcnow() DeprecationWarning

## Background

`shared/sweep-stale-tasks.sh` uses `datetime.datetime.utcnow()` in an inline Python snippet,
which is deprecated in Python 3.12+ and removed in future versions. The same deprecated call
appears in the corresponding bats test. This spec replaces both with timezone-aware equivalents.

---

## Stage 1: Replace datetime.utcnow() with datetime.now(timezone.utc)

### Description

Update the inline Python in `shared/sweep-stale-tasks.sh` and the fixture in
`test/bats/sweep-stale-tasks.bats` to use `datetime.now(timezone.utc)` instead of
`datetime.utcnow()`.

**`shared/sweep-stale-tasks.sh`** — the Python snippet that filters stale tasks:
- Add `timezone` to the import: `from datetime import datetime, timezone`
- Replace `now = datetime.utcnow()` with `now = datetime.now(timezone.utc)`
- Remove `.replace(tzinfo=None)` from the `started_dt` line — `fromisoformat` with a `+00:00`
  suffix already returns a tz-aware object, so both sides of the subtraction are now
  tz-aware and the strip is no longer needed.

**`test/bats/sweep-stale-tasks.bats`** — the "non-stale task" fixture (line 119):
- Add `timezone` to the import: `from datetime import datetime, timedelta, timezone`
- Replace `datetime.utcnow()` with `datetime.now(timezone.utc)`

After the changes, run `make test` to confirm no regressions.

### Acceptance Criteria

- `shared/sweep-stale-tasks.sh` no longer uses `datetime.utcnow()`.
- `test/bats/sweep-stale-tasks.bats` no longer uses `datetime.utcnow()`.
- Running `shared/sweep-stale-tasks.sh` produces no `DeprecationWarning` output.
- `make test` passes with no failures.
