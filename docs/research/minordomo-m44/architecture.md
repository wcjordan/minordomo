# Research: Interactive Step Agent Foundation (minordomo-m44)

## Source of Truth

Full spec: `docs/plan/interactive-step-agent-plan.md` — Story 1 section (Stages 1–3).
GH issue: https://github.com/wcjordan/minordomo/issues/339

## Current Invocation (non-interactive)

`shared/agent-pipeline.Jenkinsfile` runs:
```bash
claude -p "$(cat ${agentPromptPath})" --output-format json \
> /tmp/claude-output.json || CLAUDE_EXIT=$?
python3 ../shared/report-token-usage.py /tmp/claude-output.json 2>&1 | tee /tmp/prompt-output.txt
python3 shared/check-run-errors.py /tmp/prompt-output.txt
```

Wrapped in `timeout(time: 120, unit: 'MINUTES')`.

## File Layout

- `minordomo-step/Jenkinsfile` — loads `shared/agent-pipeline.Jenkinsfile` with `AGENT_MODE = 'worker'`
- `shared/agent-pipeline.Jenkinsfile` — shared pipeline for planning and worker agents
- `shared/agent-settings.json` — Claude permissions + hooks template (deployed to `~/.claude/settings.json` in container)
- `minordomo-step/system-prompt.md` — worker system prompt
- `shared/apply-needs-input.sh` — three-step needs-input protocol (label, comment, reset beads)
- `shared/check-run-errors.py` — reads run log output file, exits 1 if errors detected
- `shared/report-token-usage.py` — reads `claude -p` JSON output, prints agent output + token stats

## Hooks in agent-settings.json

Currently: `PreBashCommand`, `PreCompact`, `SessionStart`. No Stop hook yet.

Stop hook format (to add for Story 1 Stage 2):
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

`asyncRewake: true` means Claude enters idle state after each turn. Hook runs in background.
Hook exit code 2 + stdout text = Claude wakes up with that text as next instruction.
Hook exit code 0 = run ends normally.

## Transcript Path

Stop hook stdin JSON contains `transcript_path` (path to JSONL transcript file).
Strategy: stop hook writes this path to `/tmp/claude-transcript-path.txt` so the Jenkinsfile can read it after tmux exits (for Stage 3 log analysis).

## Log Analysis Scripts

### check-run-errors.py
- Currently: reads file at `argv[1]` (run log output from `report-token-usage.py`)
- In transcript mode: reads JSONL, extracts assistant text content, runs same `has_errors()` logic

### report-token-usage.py  
- Currently: reads single JSON (`claude -p --output-format json` output); extracts `result`, `usage`, `total_cost_usd`, `duration_ms`
- In transcript mode: reads JSONL line by line; sums `usage` across all assistant turns; last assistant text = "result"
- `total_cost_usd` and `duration_ms` may not be in per-turn transcript; output those fields only if available

## Claude Transcript JSONL Format (expected)

Each line in the transcript JSONL is a JSON object. Key entry types:
- `{"type": "user", "message": {...}}`
- `{"type": "assistant", "message": {"content": [{"type": "text", "text": "..."}], "usage": {"input_tokens": N, "output_tokens": N, "cache_read_input_tokens": N, ...}}}`

Worker should verify actual format by inspecting a real transcript before implementing Stage 3.

## tmux Invocation

Synchronous (blocks until Claude exits):
```bash
tmux new-session -- claude <args>
```
Jenkins `sh` step exits when tmux exits; exit code propagates.

System prompt for interactive mode: `claude` does not take `-p` flag in interactive mode.
Must use `--system-prompt-file <path>` or env var. Worker should verify the exact flag.

## Backwards Compatibility

- `INTERACTIVE_MODE=false` (default): identical to current behavior
- `minordomo-plan` always uses old path (no `INTERACTIVE_MODE` parameter needed there)
- Both log analysis scripts: if `--transcript` flag absent, stdin/old behavior unchanged
