#!/usr/bin/env bats
# Tests for shared/check-usage.py

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/shared/check-usage.py"
    TMP_DIR="$(mktemp -d)"
    export REPO_ROOT SCRIPT TMP_DIR

    # Write default fixture: 30% utilization (below threshold)
    cat > "$TMP_DIR/response.json" <<'EOF'
{"seven_day": {"utilization": 30}}
EOF

    python3 - <<'PYEOF' &
import http.server, os

RESPONSE_FILE = os.environ['TMP_DIR'] + '/response.json'

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = open(RESPONSE_FILE, 'rb').read()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

http.server.HTTPServer(('127.0.0.1', 18999), Handler).serve_forever()
PYEOF
    MOCK_PID=$!
    sleep 0.3  # let server bind
    export MOCK_PID

    export CLAUDE_CODE_OAUTH_TOKEN="test-token"
    export CLAUDE_USAGE_API_URL="http://127.0.0.1:18999/usage"
}

teardown() {
    kill "$MOCK_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}

@test "utilization below threshold (30%) exits 0 with action proceed" {
    cat > "$TMP_DIR/response.json" <<'EOF'
{"seven_day": {"utilization": 30}}
EOF
    run python3 "$SCRIPT"
    [ "$status" -eq 0 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'])")"
    [ "$result" = "proceed" ]
}

@test "utilization at threshold (50%) exits 1 with action exit" {
    cat > "$TMP_DIR/response.json" <<'EOF'
{"seven_day": {"utilization": 50}}
EOF
    run python3 "$SCRIPT"
    [ "$status" -eq 1 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'])")"
    [ "$result" = "exit" ]
}

@test "utilization above threshold (75%) exits 1 with action exit" {
    cat > "$TMP_DIR/response.json" <<'EOF'
{"seven_day": {"utilization": 75}}
EOF
    run python3 "$SCRIPT"
    [ "$status" -eq 1 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'])")"
    [ "$result" = "exit" ]
}

@test "CLAUDE_CODE_OAUTH_TOKEN not set exits 0 fail-open with warning" {
    unset CLAUDE_CODE_OAUTH_TOKEN
    run python3 "$SCRIPT"
    [ "$status" -eq 0 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'], d.get('warning',''))")"
    [[ "$result" == "proceed"* ]]
}

@test "server returns non-200 status exits 0 fail-open with warning" {
    # Kill the 200-returning mock server and start one that returns 503
    kill "$MOCK_PID" 2>/dev/null || true
    sleep 0.1

    python3 - <<'PYEOF' &
import http.server

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(503)
        self.end_headers()
    def log_message(self, *args): pass

http.server.HTTPServer(('127.0.0.1', 18999), Handler).serve_forever()
PYEOF
    MOCK_PID=$!
    sleep 0.3
    export MOCK_PID

    run python3 "$SCRIPT"
    [ "$status" -eq 0 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'])")"
    [ "$result" = "proceed" ]
}

@test "server returns malformed JSON exits 0 fail-open with warning" {
    cat > "$TMP_DIR/response.json" <<'EOF'
not valid json {{{
EOF
    run python3 "$SCRIPT"
    [ "$status" -eq 0 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'])")"
    [ "$result" = "proceed" ]
}

@test "response missing seven_day.utilization exits 0 fail-open with warning" {
    cat > "$TMP_DIR/response.json" <<'EOF'
{"other_field": {"utilization": 30}}
EOF
    run python3 "$SCRIPT"
    [ "$status" -eq 0 ]
    result="$(echo "$output" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['action'])")"
    [ "$result" = "proceed" ]
}
