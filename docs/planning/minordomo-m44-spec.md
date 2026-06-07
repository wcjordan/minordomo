# Implementation Plan: Interactive Step Agent Foundation (Story 1)

GH Issue: https://github.com/wcjordan/minordomo/issues/339

Introduces tmux-based invocation, the Stop hook, and the feature flag. When the agent needs human input it falls back to the existing needs-input protocol. No Discord bot required. Existing behaviour is unchanged when `INTERACTIVE_MODE=false`.

Full design context: `docs/plan/interactive-step-agent-plan.md` — Story 1 section.

---

## Stage 1: Feature flag and tmux invocation

### Description

Add an `INTERACTIVE_MODE` boolean build parameter (default `false`) to `shared/agent-pipeline.Jenkinsfile`. The GH issue says to add it to `minordomo-step/Jenkinsfile`, but `properties()` must be called from inside the pipeline definition in `shared/agent-pipeline.Jenkinsfile` — that is where all other parameters are already defined. Add it there alongside `BEADS_TASK_ID`.

Branch on `params.INTERACTIVE_MODE` in the worker stage's `sh` step:

- **`INTERACTIVE_MODE=false`** (default): run `claude -p "$(cat ...)" --output-format json > /tmp/claude-output.json` exactly as today. Keep the 120-minute `timeout()` wrapper.
- **`INTERACTIVE_MODE=true`**: run `claude` interactively via a synchronous tmux session. Remove the `timeout()` wrapper for this path only — interactive sessions can run indefinitely. Claude must receive the system prompt: verify the exact flag via `claude --help` (likely `--system-prompt-file <path>`), write the prompt to a temp file, and pass it. The tmux invocation must be synchronous (not detached) so the Jenkins `sh` step blocks until the session exits and propagates the exit code:
  ```bash
  tmux new-session -- claude --system-prompt-file /tmp/system-prompt.md
  ```
  After Claude exits, write `/tmp/claude-output.json` as an empty JSON object `{}` for this path so downstream steps that unconditionally read that file do not fail. (Stage 3 supersedes this with the `--transcript` flag; the empty file is a temporary compatibility shim.)

Restructure the `sh` step to use separate `if/else` branches for `INTERACTIVE_MODE` rather than inline conditionals, so both paths remain readable.

The `INTERACTIVE_MODE` parameter affects the worker stage only (`AGENT_MODE == 'worker'`). No changes to `minordomo-plan/Jenkinsfile` or the planning stage.

Also export `INTERACTIVE_MODE` as a shell env var in the Jenkinsfile before calling `bootstrap.sh`, so subprocesses (including the stop hook in Stage 2) can read it:
```groovy
env.INTERACTIVE_MODE = params.INTERACTIVE_MODE ? 'true' : 'false'
```

### Acceptance Criteria

- `INTERACTIVE_MODE=false` runs exactly as today — no behaviour change for tests, invocation, or output files.
- `INTERACTIVE_MODE=true` starts a synchronous tmux session running `claude` interactively; the Jenkins step exits when the session ends and the exit code is the Claude exit code.
- `INTERACTIVE_MODE=true` does not apply the 120-minute timeout.
- `make test` (shellcheck + bats) passes.

---

## Stage 2: Stop hook with auto-confirm and needs-input fallback

### Description

Write `shared/claude-stop-hook.js`. The hook is invoked by Claude Code after each assistant turn via the `Stop` event. It receives a JSON object on stdin containing (at minimum) `transcript_path` — the path to the JSONL transcript file Claude is writing to.

**Step 0 — scope guard**: if the `INTERACTIVE_MODE` env var is not `"true"`, write nothing to stdout and exit code `0` immediately. This ensures the hook is a no-op for all `claude -p` planning-agent runs even though it is present in `agent-settings.json`.

**Step 1 — transcript path capture**: write the `transcript_path` value from the hook JSON to `/tmp/claude-transcript-path.txt` (for Stage 3 to use after tmux exits).

**Step 2 — read last assistant message**: read the JSONL file at `transcript_path` line by line, find the last entry with `type == "assistant"`, and extract its text content.

**Step 3 — branch on NEEDS_INPUT:**
- **No `NEEDS_INPUT:` prefix**: write `"Confirmed, please proceed."` to stdout and exit code `2` (asyncRewake — Claude wakes and receives this as its next instruction).
- **`NEEDS_INPUT:` prefix**: extract the question text (everything after `NEEDS_INPUT:`). Invoke `shared/apply-needs-input.sh` to apply the label, post a comment, and reset beads — same behaviour as today. Exit code `0` (run ends).

**Deriving GH_ISSUE_NUMBER for `apply-needs-input.sh`**: `shared/setup-workspace.sh` already derives `GH_ISSUE_NUMBER` from `get-story-key.sh` but stores it in `_GH_ISSUE_NUMBER` (not exported). As part of this stage, change that variable name to `GH_ISSUE_NUMBER` and add it to the `export` line on line 26:
```bash
export EPIC_KEY REPO GH_ISSUE_NUMBER
```
Then in the stop hook, `GH_ISSUE_NUMBER`, `REPO`, and `BEADS_TASK_ID` are all available as env vars. Pass them to `apply-needs-input.sh`:
```javascript
spawnSync('shared/apply-needs-input.sh', [repo, ghIssueNumber, beadsTaskId, question], {stdio: 'inherit'});
```

Write `shared/claude-stop-hook.js` as a Node.js script (consistent with `shared/discord-send.js`). Use only Node.js built-ins (`fs`, `child_process`, `readline`) — no new npm dependencies.

Add the Stop hook to `shared/agent-settings.json`:
```json
"Stop": [
  {
    "hooks": [
      {
        "command": "node shared/claude-stop-hook.js",
        "type": "command",
        "asyncRewake": true
      }
    ],
    "matcher": ""
  }
]
```

Update `minordomo-step/system-prompt.md`:
- Add the `NEEDS_INPUT:` convention under a new section: "When you cannot proceed without human input, begin your response with `NEEDS_INPUT:` followed by your question. In all other cases, continue autonomously without this prefix."
- Remove the instructions that directly invoke `apply-needs-input.sh` (the Stop hook handles that for interactive mode). Keep the non-interactive needs-input flow instructions for `INTERACTIVE_MODE=false` runs.

### Acceptance Criteria

- When Claude's last message has no `NEEDS_INPUT:` prefix: hook writes `"Confirmed, please proceed."` to stdout and exits `2`. Claude wakes and continues.
- When Claude's last message starts with `NEEDS_INPUT:`: hook invokes `apply-needs-input.sh` with the question text and exits `0`. Run ends, GH issue labelled, beads task reset — same as today.
- When `INTERACTIVE_MODE` env var is not `"true"` (planning agent, non-interactive worker): hook exits `0` immediately without touching the transcript or calling any external script.
- Hook writes `transcript_path` to `/tmp/claude-transcript-path.txt` on every invocation where `INTERACTIVE_MODE=true`.
- `GH_ISSUE_NUMBER` is exported from `setup-workspace.sh` and available in the tmux session environment.
- Manual test with a dummy transcript file confirms both branches work.
- `make test` passes.

---

## Stage 3: Update log analysis scripts for transcript mode

### Description

Add `--transcript <path>` flag to `shared/check-run-errors.py` and `shared/report-token-usage.py`. When the flag is passed, each script reads and parses the Claude Code transcript JSONL at `<path>` instead of the `claude -p` JSON output. When the flag is absent, existing file-based behaviour is unchanged (full backwards compatibility).

**Before implementing**, inspect the actual JSONL format by running `claude` briefly in interactive mode and examining the transcript. Key things to verify:
- The JSON structure of `assistant` type entries (particularly the `usage` field layout and text content path)
- Whether `total_cost_usd` or `duration_ms` appear anywhere in the transcript (or need to be omitted in transcript mode)

**`report-token-usage.py --transcript <path>`**:
1. Read the JSONL file, parse each line as JSON.
2. Find all entries where `type == "assistant"` (verify the actual field name from a real transcript).
3. Extract the text content from the last assistant entry and print it under `=== Agent Output ===` (same header as today).
4. Sum `input_tokens`, `output_tokens`, and `cache_read_input_tokens` (or equivalent) across all assistant entries. Print under `=== Token Usage ===`.
5. Print `Cost (USD)` and `Duration` only if available in the transcript; omit those lines rather than printing zeros if unavailable.

**`check-run-errors.py --transcript <path>`**:
1. Read the JSONL file, parse each line as JSON.
2. Collect the text content from all assistant entries into a single string.
3. Run the existing `has_errors()` logic on that combined string (unchanged).

Update `shared/agent-pipeline.Jenkinsfile` to pass `--transcript` when `INTERACTIVE_MODE=true`. Use the path written to `/tmp/claude-transcript-path.txt` by the stop hook. Also remove the Stage 1 workaround that wrote `{}` to `/tmp/claude-output.json` for the interactive path:
```bash
# in the INTERACTIVE_MODE=true sh block (replaces the report-token-usage call):
TRANSCRIPT_PATH=$(cat /tmp/claude-transcript-path.txt 2>/dev/null || echo "")
if [ -n "$TRANSCRIPT_PATH" ]; then
    python3 shared/report-token-usage.py --transcript "$TRANSCRIPT_PATH" 2>&1 | tee /tmp/prompt-output.txt || true
    python3 shared/check-run-errors.py --transcript "$TRANSCRIPT_PATH" /tmp/prompt-output.txt
else
    # fallback if hook never wrote the path (e.g. Claude exited before first Stop)
    python3 shared/report-token-usage.py /tmp/claude-output.json 2>&1 | tee /tmp/prompt-output.txt || true
    python3 shared/check-run-errors.py /tmp/prompt-output.txt
fi
```

For `INTERACTIVE_MODE=false` (and for `minordomo-plan`), the calls to both scripts are unchanged.

Add bats tests for the new `--transcript` flag behaviour in:
- `test/bats/report-token-usage.bats` — add tests for `--transcript` with a JSONL fixture
- `test/bats/check-run-errors.bats` — add tests for `--transcript` with a JSONL fixture

Add a JSONL transcript fixture at `test/fixtures/claude-transcript-success.jsonl` (at minimum: one user turn and one assistant turn with a successful run log JSON block in the assistant text, matching the actual transcript format verified during implementation).

### Acceptance Criteria

- `minordomo-plan` pipeline (always `INTERACTIVE_MODE=false`) calls scripts with no new flags — no behaviour change.
- `minordomo-step` with `INTERACTIVE_MODE=true` calls `report-token-usage.py` and `check-run-errors.py` with `--transcript`; scripts parse the transcript JSONL and produce correct output.
- Both scripts still accept the old positional-arg interface when `--transcript` is absent.
- New bats tests pass for the `--transcript` code path.
- `make test` passes.
