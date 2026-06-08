# Research: helm/minordomo-cd-setup Dead Code Analysis

## Summary

`helm/minordomo-cd-setup` is confirmed dead code. It was overlooked when the Dolt SQL server
infrastructure was removed from the project.

## History

- **Commit `072e2e1`** — Added `helm/minordomo-cd-setup/` along with `helm/dolt-server/` and
  other Dolt infrastructure as part of setting up a Dolt SQL server for beads issue tracking.
  The `minordomo-cd-setup` chart creates two Kubernetes secrets (`dolt-root-password` and
  `dolt-minordomo-password`) that Jenkins uses to authenticate to the Dolt server.

- **Commit `58c00c9`** — Switched beads from Dolt SQL server mode to embedded/JSONL mode.
  This removed `helm/dolt-server/`, `scripts/dolt-forward.sh`, `scripts/dolt-setup.sh`,
  and related pipeline infrastructure. However, `helm/minordomo-cd-setup/` was **not** removed.

## Dead Code Conclusion

`helm/minordomo-cd-setup` is dead because:
1. The Dolt SQL server (`helm/dolt-server/`) no longer exists — removed in commit `58c00c9`
2. The secrets it creates (`dolt-root-password`, `dolt-minordomo-password`) are not referenced
   anywhere in the current codebase except within the chart itself
3. The `make setup-cd` Makefile target that deploys this chart is not called from any pipeline
   or script
4. No documentation references this chart

## Related Artifacts to Clean Up

The following are also dead (introduced alongside the chart, never removed):

1. **`helm/minordomo-cd-setup/`** — the chart itself (3 files)
2. **`Makefile` `setup-cd` target** — the only caller of the chart; lines 29–45
3. **`Makefile` `.env` target** — generates passwords for `setup-cd`; lines 21–27
   - Note: `.env` target may need to stay if it has other uses, but the DOLT vars are dead
4. **`.env.example`** — contains `DOLT_ROOT_PASSWORD=` and `DOLT_MINORDOMO_PASSWORD=` which
   were only needed for `make setup-cd`

## Scope of Changes

All changes fit comfortably in a single stage (~15-20 minutes):
- Delete `helm/minordomo-cd-setup/` directory (3 files)
- Remove `setup-cd` Makefile target (lines 29–45) and the `.env` target if it only serves `setup-cd`
- Remove `DOLT_ROOT_PASSWORD` and `DOLT_MINORDOMO_PASSWORD` from `.env.example`
- Verify `make test` still passes after changes
