# Auto-Export Analysis for minordomo-fsk

## Problem

`issues.jsonl` and `interactions.jsonl` are tracked in git under `.beads/`.
After each beads write operation the auto-export fires and updates `issues.jsonl`,
and `export.git-add: true` stages the file automatically. When agents commit their
work the staged `issues.jsonl` gets bundled in, causing merge conflicts whenever
two agents commit in parallel.

## Current State

### Files tracked in git under `.beads/`
- `.gitignore`
- `README.md`
- `config.yaml`
- `interactions.jsonl`
- `issues.jsonl`
- `metadata.json`

### Relevant config.yaml settings
- `export.auto: true` (default, not explicitly set) — auto-exports to `issues.jsonl` after each write
- `export.git-add: true` (default) — stages the export file automatically
- `dolt.auto-push: true` — pushes dolt data to the git remote via `refs/dolt/data`
- `backup.git-push: true` — pushes export locally but not to remote

### How export is controlled (from `bd config get` output)
- `export.auto: true` (active)
- `export.git-add: true` (active)

## Solution

1. Set `export.auto: false` in `.beads/config.yaml`. This stops `issues.jsonl` from
   being regenerated on every write. The config help shows this is the right knob:
   ```
   export.auto       Enable/disable auto-export (default: true)
   ```

2. Untrack `issues.jsonl` and `interactions.jsonl` from git (`git rm --cached`) and
   add them to `.beads/.gitignore`. Once auto-export is off these files become stale
   and should not be committed.

3. Update the CLAUDE.md reference describing `.beads/issues.jsonl` as a "passive export"
   to reflect that it is no longer exported.

## What is NOT Affected

- Dolt sync (`bd dolt pull` / `bd dolt push`) — this is the primary sync mechanism
  and is not changed.
- `beads-write.sh` — wraps writes with dolt pull/push; unaffected.
- `config.yaml`, `metadata.json`, `README.md` — remain tracked in git as before.
- `export.events` — not currently enabled, not relevant.

## References

- `bd config get export.auto` → `true` (currently enabled)
- `.beads/config.yaml` — contains `backup.git-push: true` and `dolt.auto-push: true`
- `.beads/.gitignore` — does NOT currently list `issues.jsonl` or `interactions.jsonl`
- CLAUDE.md:180 — mentions `.beads/issues.jsonl` as a "passive export"
