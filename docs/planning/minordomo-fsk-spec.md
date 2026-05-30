# Implementation Plan: Disable auto-export for beads (minordomo-fsk)

## Background

Beads auto-exports issues to `.beads/issues.jsonl` after each write operation and
auto-stages the file via `export.git-add: true`. When agents commit in parallel this
file causes merge conflicts. The Dolt sync mechanism (`bd dolt pull`/`bd dolt push`)
is the real source of truth; the JSONL export is redundant and harmful.

---

## Stage 1: Disable auto-export and untrack JSONL files

### Description

Turn off beads auto-export by setting `export.auto: false` in `.beads/config.yaml`.
Remove `issues.jsonl` and `interactions.jsonl` from git tracking with `git rm --cached`,
add them to `.beads/.gitignore` so they are not re-committed, and update the CLAUDE.md
description that refers to `.beads/issues.jsonl` as a passive export.

Specific changes:

1. **`.beads/config.yaml`** — add explicit `export.auto: false` under an `export:` key
   (alongside or near the existing `backup:` block).

2. **`.beads/.gitignore`** — append `issues.jsonl` and `interactions.jsonl` to the
   existing `# Backup data` section or under a new `# Auto-export` comment.

3. **Git untrack** — run `git rm --cached .beads/issues.jsonl .beads/interactions.jsonl`
   so the files stop appearing in diffs/commits. The files may remain on disk (stale)
   but will be ignored going forward.

4. **CLAUDE.md** — update the architecture-in-one-line sentence (line 180) to remove
   the claim that `.beads/issues.jsonl` is a passive export, since it will no longer
   be maintained.

### Acceptance Criteria

- `export.auto: false` is present in `.beads/config.yaml`.
- `issues.jsonl` and `interactions.jsonl` are listed in `.beads/.gitignore`.
- `git ls-files .beads/` no longer includes `issues.jsonl` or `interactions.jsonl`.
- CLAUDE.md no longer describes `.beads/issues.jsonl` as a passive export.
- `make test` passes.
