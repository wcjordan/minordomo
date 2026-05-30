# Research: Fix datetime.utcnow() DeprecationWarning

## Problem

Running `shared/sweep-stale-tasks.sh` emits:
```
DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version.
Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
```

Python version on the agent: 3.13.13 (where this warning is active).

## Affected Locations

Two files use `datetime.utcnow()`:

### 1. `shared/sweep-stale-tasks.sh` (line 25)

```python
from datetime import datetime
...
now = datetime.utcnow()   # naive UTC
started_dt = datetime.fromisoformat(started_at.replace('Z', '+00:00')).replace(tzinfo=None)
age_hours = (now - started_dt).total_seconds() / 3600
```

Both sides of the subtraction are stripped to naive UTC to allow comparison.

### 2. `test/bats/sweep-stale-tasks.bats` (line 119)

```python
from datetime import datetime, timedelta
recent = (datetime.utcnow() - timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ')
```

## Fix

Use `datetime.now(timezone.utc)` (available since Python 3.2) instead of `datetime.utcnow()`.

For the script: keep both datetimes timezone-aware; drop the `.replace(tzinfo=None)` strip since `fromisoformat` with `+00:00` suffix already returns a tz-aware object.

For the test: `strftime` works fine on tz-aware datetimes.

## Scope

Single-stage fix. No API or interface changes. `make test` should confirm correctness.
