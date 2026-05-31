#!/usr/bin/env python3
"""Gate on the configured time-of-day schedule.

Exits 0 if the current time is within the allowed schedule window.
Exits 1 if outside the window.
Writes a JSON object to stdout on both paths.

Usage: check-schedule.py [--now "YYYY-MM-DDTHH:MM:SS"]
"""

import argparse
import json
import os
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

import yaml


def load_config():
    config_path = os.path.join(os.path.dirname(__file__), "config.yaml")
    with open(config_path) as f:
        return yaml.safe_load(f)


def parse_time_range(range_str):
    """Parse 'HH:MM-HH:MM' into (start_minutes, end_minutes)."""
    start_str, end_str = range_str.split("-")
    sh, sm = map(int, start_str.split(":"))
    eh, em = map(int, end_str.split(":"))
    return sh * 60 + sm, eh * 60 + em


def check_schedule(now_str=None):
    config = load_config()
    schedule = config.get("schedule", {})

    tz_name = schedule.get("timezone", "America/New_York")
    allowed_days = schedule.get("allowed_days", [])
    allowed_hours = schedule.get("allowed_hours", [])
    weekend_override = schedule.get("weekend_override", False)

    tz = ZoneInfo(tz_name)

    if now_str:
        dt = datetime.fromisoformat(now_str).replace(tzinfo=tz)
    else:
        dt = datetime.now(tz)

    day_abbr = dt.strftime("%a")
    is_weekend = day_abbr in ("Sat", "Sun")

    if weekend_override and is_weekend:
        print(json.dumps({"step": "schedule_check", "status": "ok", "action": "proceed"}))
        sys.exit(0)

    if day_abbr not in allowed_days:
        print(json.dumps({
            "step": "schedule_check",
            "status": "ok",
            "action": "exit",
            "reason": "day_not_allowed",
        }))
        sys.exit(1)

    current_minutes = dt.hour * 60 + dt.minute
    for range_str in allowed_hours:
        start, end = parse_time_range(range_str)
        if start <= current_minutes <= end:
            print(json.dumps({"step": "schedule_check", "status": "ok", "action": "proceed"}))
            sys.exit(0)

    print(json.dumps({
        "step": "schedule_check",
        "status": "ok",
        "action": "exit",
        "reason": "outside_hours",
    }))
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--now", help="Override wall-clock time (ISO datetime string)")
    args = parser.parse_args()
    check_schedule(args.now)


if __name__ == "__main__":
    main()
