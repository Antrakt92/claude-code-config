#!/usr/bin/env python3
"""Log tool execution duration to ~/.claude/hook-perf.log.

Format: "<unix_ts> <tool_name> <duration_ms>" — grep+awk friendly.
Auto-rotates at 10MB → renames to .log.old (atomic os.replace).
Fail-open everywhere — telemetry must be invisible if it breaks.
"""

import json
import os
import sys
import time

LOG_PATH = os.path.expanduser("~/.claude/hook-perf.log")
ROTATE_AT_BYTES = 10 * 1024 * 1024


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError, OSError):
        sys.exit(0)

    duration = data.get("duration_ms")
    tool = data.get("tool_name")

    # Reject non-numeric (None, str), reject bool subtype of int trap.
    if not isinstance(duration, (int, float)) or isinstance(duration, bool):
        sys.exit(0)
    if not isinstance(tool, str) or not tool:
        sys.exit(0)

    # Sanitize tool name — keep awk-parseable.
    tool = tool.replace(" ", "_").replace("\t", "_")

    try:
        if os.path.exists(LOG_PATH):
            try:
                if os.path.getsize(LOG_PATH) > ROTATE_AT_BYTES:
                    os.replace(LOG_PATH, LOG_PATH + ".old")
            except OSError:
                pass

        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(f"{int(time.time())} {tool} {int(duration)}\n")
    except OSError:
        pass


if __name__ == "__main__":
    main()
