# MDOMO-22: Measure Claude Token Usage by Job

Track token usage (input tokens, cache tokens, output tokens, cost) for each job type
(majordomo, plan, step) so the orchestration overhead can be estimated.

---

## Stage 1: Token usage reporting script

### Description

Create `shared/report-token-usage.py` — a Python script that reads Claude's
`--output-format json` output from a file, prints the agent's run log text, then
prints a token usage summary (input tokens, cache read tokens, output tokens, cost,
and duration). Also add bats tests and fixture JSON files so the script is covered
by `make test`.

The script accepts a single positional argument: the path to the JSON file produced
by `claude --output-format json`. It exits 0 in all cases (reporting failures must
not mask Claude exit codes). Its output goes to stdout so it appears in the Jenkins
build log.

Expected printed format:
```
=== Agent Output ===
<content of result field from Claude JSON>

=== Token Usage ===
  Input tokens:      12,345
  Cache read tokens: 40,000
  Output tokens:      3,456
  Cost (USD):        $0.1234
  Duration:          42.1s
```

Fixture files to add:
- `test/fixtures/claude-output-success.json` — a representative success JSON
- `test/fixtures/claude-output-error.json` — a representative error JSON

Bats tests (`test/bats/report-token-usage.bats`) cover:
- Prints "=== Token Usage ===" section
- Correctly formats all five metric fields from the fixture
- Exits 0 on a success fixture
- Exits 0 on an error fixture (does not propagate `is_error`)
- Exits 0 when given a nonexistent file (graceful fallback)

### Acceptance Criteria

- `shared/report-token-usage.py` exists and is executable
- Running it with `test/fixtures/claude-output-success.json` prints input tokens,
  cache read tokens, output tokens, cost, and duration
- Running it with a nonexistent path prints a warning and exits 0
- `make test` passes (shellcheck, prompt validation, dry-run, bats all green)

---

## Stage 2: Capture token usage in all three Jenkinsfiles

### Description

Update `majordomo/Jenkinsfile`, `minordomo-plan/Jenkinsfile`, and
`minordomo-step/Jenkinsfile` to:

1. Add `--output-format json` to the `claude -p` invocation and redirect stdout to
   `/tmp/claude-output.json`, capturing the exit code without triggering `set -e`:
   ```bash
   CLAUDE_EXIT=0
   claude -p "$(cat <system-prompt>)" --output-format json \
     > /tmp/claude-output.json || CLAUDE_EXIT=$?
   ```

2. Call the reporting script (best-effort; never fail the build on its own):
   ```bash
   python3 shared/report-token-usage.py /tmp/claude-output.json || true
   ```

3. Propagate Claude's original exit code:
   ```bash
   exit $CLAUDE_EXIT
   ```

The net effect: the Jenkins build log shows the agent's run log text followed by a
token usage summary for every build. Build success/failure is governed solely by
Claude's exit code, unchanged from today.

### Acceptance Criteria

- All three Jenkinsfiles use `--output-format json` and call `report-token-usage.py`
- A failed Claude run (exit 1) still fails the Jenkins build
- A successful Claude run (exit 0) still passes the Jenkins build
- Token usage summary (input, cache read, output tokens and cost) is visible in the
  Jenkins build log after each run
- `make test` passes
