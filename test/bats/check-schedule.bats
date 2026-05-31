#!/usr/bin/env bats
# Tests for shared/check-schedule.py

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/check-schedule.py"
    export SCRIPT
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

@test "Saturday with weekend_override false exits 1 with reason day_not_allowed" {
    # Saturday 2026-01-03 at 07:00 — Sat not in allowed_days, override=false
    run python3 "$SCRIPT" --now "2026-01-03T07:00:00"
    [ "$status" -eq 1 ]
    echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['action']=='exit'; assert d['reason']=='day_not_allowed', d"
}

@test "Saturday with weekend_override true exits 0" {
    # Temporarily override config via a patched config approach — use env trick
    # We write a patched config to a temp file and patch the script's load path
    TMP_DIR="$(mktemp -d)"
    CONFIG_SRC="$REPO_ROOT/shared/config.yaml"
    python3 -c "
import yaml, sys
with open('$CONFIG_SRC') as f:
    cfg = yaml.safe_load(f)
cfg['schedule']['weekend_override'] = True
with open('$TMP_DIR/config.yaml', 'w') as f:
    yaml.dump(cfg, f)
"
    # Patch: copy script to tmp dir, point it at patched config
    cp "$SCRIPT" "$TMP_DIR/check-schedule.py"
    sed -i "s|os.path.dirname(__file__)|'$TMP_DIR'|g" "$TMP_DIR/check-schedule.py"

    # Saturday 2026-01-03 at 12:00
    run python3 "$TMP_DIR/check-schedule.py" --now "2026-01-03T12:00:00"
    rm -rf "$TMP_DIR"
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
