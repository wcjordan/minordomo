#!/usr/bin/env bats
# Tests for shared/check-schedule.py

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMP_DIR="$(mktemp -d)"
    export REPO_ROOT TMP_DIR

    # Write a known test config (limited hours) so tests
    # are independent of the production config values in shared/config.yaml.
    cat > "$TMP_DIR/config.yaml" <<'EOF'
schedule:
  allowed_days: [Mon, Tue, Wed, Thu, Fri, Sat, Sun]
  allowed_hours: ["00:00-08:00"]
  timezone: America/New_York
EOF

    cp "$REPO_ROOT/shared/check-schedule.py" "$TMP_DIR/check-schedule.py"
    python3 - "$TMP_DIR/check-schedule.py" "$TMP_DIR" <<'PYEOF'
import sys, pathlib
path, config_dir = sys.argv[1], sys.argv[2]
src = pathlib.Path(path).read_text()
src = src.replace("os.path.dirname(__file__)", repr(config_dir))
pathlib.Path(path).write_text(src)
PYEOF

    SCRIPT="$TMP_DIR/check-schedule.py"
    export SCRIPT
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "weekday in allowed hours exits 0" {
    # Monday 2026-01-05 at 07:00 — within 00:00-08:00
    run python3 "$SCRIPT" --now "2026-01-05T07:00:00"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='proceed', d"
}

@test "weekday outside allowed hours exits 1 with reason outside_hours" {
    # Monday 2026-01-05 at 12:00 — between 08:00 and 18:00, outside allowed windows
    run python3 "$SCRIPT" --now "2026-01-05T12:00:00"
    [ "$status" -eq 1 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='exit'; assert d['reason']=='outside_hours', d"
}

@test "Saturday not in allowed_days exits 1 with reason day_not_allowed" {
    python3 -c "
import yaml, pathlib, os
cfg_path = os.environ['TMP_DIR'] + '/config.yaml'
cfg = yaml.safe_load(open(cfg_path))
cfg['schedule']['allowed_days'] = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']
open(cfg_path, 'w').write(yaml.dump(cfg))
"
    # Saturday 2026-01-03 at 07:00 — Sat not in allowed_days
    run python3 "$SCRIPT" --now "2026-01-03T07:00:00"
    [ "$status" -eq 1 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='exit'; assert d['reason']=='day_not_allowed', d"
}

@test "Saturday in allowed_days exits 0" {
    # Saturday 2026-01-03 at 07:00 — Sat in allowed_days (production-style config), within hours
    run python3 "$SCRIPT" --now "2026-01-03T07:00:00"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='proceed', d"
}

@test "time exactly at range boundary exits 0 (inclusive)" {
    # Monday 2026-01-05 at 00:00 — exactly at start of 00:00-08:00 range
    run python3 "$SCRIPT" --now "2026-01-05T00:00:00"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='proceed', d"

    # Monday 2026-01-05 at 08:00 — exactly at end of 00:00-08:00 range
    run python3 "$SCRIPT" --now "2026-01-05T08:00:00"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='proceed', d"
}
