# Plan: Remove the cron that excludes running on the weekend

## Overview

The Majordomo Jenkins job is currently scheduled to run only Monday–Friday via the cron expression `H/30 * * * 1-5`. This change removes the weekday-only restriction so the pipeline runs every day, including Saturdays and Sundays.

A secondary cleanup removes the `weekend_override` mechanism from `config.yaml` and `check-schedule.py`, which was introduced to allow manually-triggered runs on weekends to proceed through the schedule gate even though the cron never triggered on those days.

---

## Stage 1: Update the Jenkins cron to run on all days

### Description

Change the Majordomo Jenkinsfile cron trigger from `H/30 * * * 1-5` (Mon–Fri only) to `H/30 * * * *` (every day). This is the only change required to allow weekend runs.

No other files need to change for correctness: `shared/check-schedule.py` already allows weekend runs via `weekend_override: true` in `config.yaml`.

### Acceptance Criteria

- `majordomo/Jenkinsfile` cron expression reads `H/30 * * * *` (not `1-5`)
- `make test` passes

---

## Stage 2: Remove the weekend_override mechanism

### Description

Now that the cron runs on weekends, the `weekend_override` field in `config.yaml` is no longer needed — it was a workaround for the trigger restriction. This stage cleans it up:

1. Update `shared/config.yaml`: add `Sat` and `Sun` to `allowed_days`; remove the `weekend_override` key.
2. Update `shared/check-schedule.py`: remove the `weekend_override` early-exit branch (the `if weekend_override and is_weekend` block and the `weekend_override = ...` assignment above it).
3. Update `test/bats/check-schedule.bats`:
   - Remove the `Saturday with weekend_override true exits 0` test (it tests removed logic).
   - Update the `Saturday with weekend_override false exits 1` test to `Saturday not in allowed_days exits 1` using a config that omits `Sat`.
   - Add a `Saturday in allowed_days exits 0` test using the production-style config (which now includes `Sat`).

### Acceptance Criteria

- `shared/config.yaml` has `allowed_days: [Mon, Tue, Wed, Thu, Fri, Sat, Sun]` and no `weekend_override` key
- `shared/check-schedule.py` has no reference to `weekend_override`
- `test/bats/check-schedule.bats` has no reference to `weekend_override`
- `make test` passes
