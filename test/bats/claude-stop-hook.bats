#!/usr/bin/env bats
# Tests for shared/claude-stop-hook.js

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/claude-stop-hook.js"
    export SCRIPT

    TRANSCRIPT="$BATS_TEST_TMPDIR/transcript.jsonl"
    export TRANSCRIPT
}

make_transcript() {
    local text="$1"
    printf '%s\n%s\n' \
        '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Do the task"}]}}' \
        "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"$text\"}]}}" \
        > "$TRANSCRIPT"
}

make_hook_input() {
    echo "{\"transcript_path\":\"$TRANSCRIPT\"}"
}

# Create a fake CWD with a stub shared/apply-needs-input.sh that records its args.
# Sets FAKE_CWD and STUB_OUT in the calling scope.
setup_fake_cwd() {
    FAKE_CWD="$BATS_TEST_TMPDIR/fakecwd"
    STUB_OUT="$BATS_TEST_TMPDIR/stub-out.txt"
    mkdir -p "$FAKE_CWD/shared"
    cat > "$FAKE_CWD/shared/apply-needs-input.sh" << STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$STUB_OUT"
exit 0
STUB
    chmod +x "$FAKE_CWD/shared/apply-needs-input.sh"
    export FAKE_CWD STUB_OUT
}

@test "exits 0 immediately when INTERACTIVE_MODE is not set" {
    run env -u INTERACTIVE_MODE node "$SCRIPT" <<< '{"transcript_path":"/nonexistent"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "exits 0 immediately when INTERACTIVE_MODE=false" {
    run env INTERACTIVE_MODE=false node "$SCRIPT" <<< '{"transcript_path":"/nonexistent"}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "no NEEDS_INPUT prefix: exits 2 and writes confirm message to stdout" {
    make_transcript "I have completed the implementation."
    run env INTERACTIVE_MODE=true node "$SCRIPT" <<< "$(make_hook_input)"
    [ "$status" -eq 2 ]
    [ "$output" = "Confirmed, please proceed." ]
}

@test "no NEEDS_INPUT prefix: writes transcript path to /tmp file" {
    make_transcript "All done."
    env INTERACTIVE_MODE=true node "$SCRIPT" <<< "$(make_hook_input)" || true
    [ "$(cat /tmp/claude-transcript-path.txt)" = "$TRANSCRIPT" ]
}

@test "NEEDS_INPUT prefix: exits 0" {
    setup_fake_cwd
    make_transcript "NEEDS_INPUT: What is the API endpoint URL?"
    cd "$FAKE_CWD"
    run env INTERACTIVE_MODE=true REPO=myrepo GH_ISSUE_NUMBER=42 BEADS_TASK_ID=beads-123 \
        node "$SCRIPT" <<< "$(make_hook_input)"
    [ "$status" -eq 0 ]
}

@test "NEEDS_INPUT prefix: invokes apply-needs-input.sh with correct args" {
    setup_fake_cwd
    make_transcript "NEEDS_INPUT: What is the API endpoint URL?"
    cd "$FAKE_CWD"
    env INTERACTIVE_MODE=true REPO=myrepo GH_ISSUE_NUMBER=42 BEADS_TASK_ID=beads-123 \
        node "$SCRIPT" <<< "$(make_hook_input)"
    [ -f "$STUB_OUT" ]
    # Each arg on its own line
    [ "$(sed -n '1p' "$STUB_OUT")" = "myrepo" ]
    [ "$(sed -n '2p' "$STUB_OUT")" = "42" ]
    [ "$(sed -n '3p' "$STUB_OUT")" = "beads-123" ]
    [ "$(sed -n '4p' "$STUB_OUT")" = "What is the API endpoint URL?" ]
}

@test "NEEDS_INPUT prefix: writes transcript path before invoking apply-needs-input.sh" {
    setup_fake_cwd
    make_transcript "NEEDS_INPUT: Please clarify scope."
    cd "$FAKE_CWD"
    env INTERACTIVE_MODE=true REPO=r GH_ISSUE_NUMBER=1 BEADS_TASK_ID=t \
        node "$SCRIPT" <<< "$(make_hook_input)"
    [ "$(cat /tmp/claude-transcript-path.txt)" = "$TRANSCRIPT" ]
}

@test "handles leading whitespace before NEEDS_INPUT" {
    setup_fake_cwd
    make_transcript "  NEEDS_INPUT: What branch should I target?"
    cd "$FAKE_CWD"
    run env INTERACTIVE_MODE=true REPO=r GH_ISSUE_NUMBER=1 BEADS_TASK_ID=t \
        node "$SCRIPT" <<< "$(make_hook_input)"
    [ "$status" -eq 0 ]
}

@test "successful run log JSON in last message: exits 0" {
    node -e "
const fs = require('fs');
const runLog = {run_id:'jenkins-42',timestamp:'2026-06-10T00:00:00Z',beads_task_id:'minordomo-123.1',status:'success',steps:[],errors:[]};
const lines = [
  JSON.stringify({type:'user',message:{role:'user',content:[{type:'text',text:'Do the task'}]}}),
  JSON.stringify({type:'assistant',message:{role:'assistant',content:[{type:'text',text:JSON.stringify(runLog)}]}})
];
fs.writeFileSync('$TRANSCRIPT', lines.join('\n') + '\n');
"
    run env INTERACTIVE_MODE=true node "$SCRIPT" <<< "$(make_hook_input)"
    [ "$status" -eq 0 ]
}

@test "failed run log JSON in last message: exits 2 with confirm message" {
    node -e "
const fs = require('fs');
const runLog = {run_id:'jenkins-42',timestamp:'2026-06-10T00:00:00Z',beads_task_id:'minordomo-123.1',status:'failure',steps:[],errors:['something broke']};
const lines = [
  JSON.stringify({type:'user',message:{role:'user',content:[{type:'text',text:'Do the task'}]}}),
  JSON.stringify({type:'assistant',message:{role:'assistant',content:[{type:'text',text:JSON.stringify(runLog)}]}})
];
fs.writeFileSync('$TRANSCRIPT', lines.join('\n') + '\n');
"
    run env INTERACTIVE_MODE=true node "$SCRIPT" <<< "$(make_hook_input)"
    [ "$status" -eq 2 ]
    [ "$output" = "Confirmed, please proceed." ]
}

@test "exits 1 on invalid JSON input" {
    run env INTERACTIVE_MODE=true node "$SCRIPT" <<< "not-json"
    [ "$status" -eq 1 ]
}

@test "exits 1 when transcript_path is missing from hook input" {
    run env INTERACTIVE_MODE=true node "$SCRIPT" <<< '{}'
    [ "$status" -eq 1 ]
}
