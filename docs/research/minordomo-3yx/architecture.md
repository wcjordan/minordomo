# Research: Remove weekend cron restriction (minordomo-3yx)

## Problem

The Majordomo Jenkins job is cron-triggered only on weekdays (Mon–Fri). The cron expression in `majordomo/Jenkinsfile` line 11:

```
cron(env.BRANCH_NAME == 'main' ? 'H/30 * * * 1-5' : '')
```

`1-5` = days of week Monday–Friday (Jenkins/cron numbering: 1=Mon, 5=Fri). This prevents the pipeline from running on Saturdays and Sundays.

## Existing weekend-awareness logic

There is a **separate** in-job schedule gate in `shared/check-schedule.py`, called from the Jenkinsfile after the job is triggered:

- `shared/config.yaml` `schedule` section:
  - `allowed_days: [Mon, Tue, Wed, Thu, Fri]`
  - `weekend_override: true`
  - `allowed_hours: ["00:00-23:59"]`

`check-schedule.py` exits 0 if:
1. `weekend_override: true` AND it's Saturday or Sunday → proceed immediately
2. OR current day is in `allowed_days` AND current time is in `allowed_hours`

Since `weekend_override: true`, the schedule gate already allows weekend runs. The **only blocker is the Jenkins cron trigger** itself.

## Minimum fix

Change `H/30 * * * 1-5` → `H/30 * * * *` in `majordomo/Jenkinsfile`.

## Optional cleanup

The `weekend_override` mechanism exists only to paper over the fact that `allowed_days` doesn't include weekends. After fixing the cron, it's cleaner to:
- Add `Sat` and `Sun` to `allowed_days` in `config.yaml`
- Remove `weekend_override` from `config.yaml`
- Remove the `weekend_override` branch from `check-schedule.py`
- Update `test/bats/check-schedule.bats` (one test becomes obsolete, replace with Sat-in-allowed_days test)

## Files affected

| File | Change |
|---|---|
| `majordomo/Jenkinsfile` | Change cron `1-5` → `*` |
| `shared/config.yaml` | Add `Sat`, `Sun` to `allowed_days`; remove `weekend_override` |
| `shared/check-schedule.py` | Remove `weekend_override` branch (~5 lines) |
| `test/bats/check-schedule.bats` | Update/replace the `weekend_override true` test |
