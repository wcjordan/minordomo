# Spec: Spec Evolution — Explicit Handling When Workers Update the Plan Mid-Implementation

GH Issue: https://github.com/wcjordan/minordomo/issues/209

## Background

Workers already branch from the feature branch tip and read the spec doc, so spec updates propagate mechanically to later stages. This work makes the behaviour intentional: explicit instructions in the worker prompt, a defined PR-body format for spec changes, and a test that validates the path.

Majordomo Step 9 already deletes the spec doc and research docs before opening the feature→main PR, so spec evolution is fully cleaned up at that point. No Majordomo changes are needed.

---

## Stage 1: Update Worker System Prompt with Explicit Spec-Update Instructions

### Description

Update `minordomo-step/system-prompt.md` to make spec-update behaviour explicit in two places:

1. **Step 3 (Implement the Stage)** — Replace the current one-liner with an explicit instruction block that:
   - Names the exact file to update: `docs/planning/${EPIC_KEY}-spec.md`
   - Describes when an update is warranted (approach changes, scope adjustments, guidance corrections for later stages)
   - Tells the worker to note what changed and why, for use in the PR body

2. **Step 5 (Commit and Push)** — Add an explicit note that any spec doc changes must be staged alongside implementation changes. The current text already mentions this ("including any spec doc updates") but make it unambiguous.

3. **Step 6 (Open PR)** — Update the PR body template to include an explicit `## Spec Changes` section (conditional on whether the spec was updated) that summarises what changed and why:
   ```
   ## Spec Changes (if applicable)
   - <brief description of what changed in the spec doc and why>
   ```
   The run log `implement` step should record `spec_updated: true/false`.

4. **Run log format** — Add `spec_updated: true|false` to the `implement` step entry so orchestration tooling can detect spec changes without parsing PR bodies.

### Acceptance Criteria

- `minordomo-step/system-prompt.md` Step 3 explicitly instructs the worker to update `docs/planning/${EPIC_KEY}-spec.md` when the plan changes, naming the file path and describing when updates are warranted
- `minordomo-step/system-prompt.md` Step 6 instructs the worker to include a `## Spec Changes` section in the PR body when the spec was updated, with a summary of what changed
- The run log format shows `spec_updated: true|false` in the `implement` step
- `make test` passes

---

## Stage 2: Add Spec-Update Path Validation Test

### Description

Add a test that validates the spec-update path end-to-end at the git-workflow level. Because the worker is an AI agent, we cannot test its decision-making, but we can test that the git machinery correctly captures spec doc changes in commits.

Add `test/bats/worker-spec-update.bats` with tests that:
1. Set up a temp git repo containing a spec doc
2. Simulate a worker modifying the spec doc (as Claude would do)
3. Verify that `git add -A && git commit` includes the spec doc changes
4. Verify the commit history shows the spec doc was modified

Also extend `test/validate-prompts.py` to check that the worker system prompt (`minordomo-step/system-prompt.md`) contains all three required spec-update phrases:
- A reference to `docs/planning/` (spec doc path)
- "Spec Changes" (PR body section heading)
- `spec_updated` (run log field)

This combination validates the spec-update path at two levels: git behaviour (bats) and prompt content (validate-prompts.py).

### Acceptance Criteria

- `test/bats/worker-spec-update.bats` exists with at least 2 tests covering the spec-doc-in-commit path
- `test/validate-prompts.py` checks that `minordomo-step/system-prompt.md` contains required spec-update phrases (`docs/planning/`, `Spec Changes`, `spec_updated`)
- `make test` passes (all new tests pass, no regressions)
