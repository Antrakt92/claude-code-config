#!/usr/bin/env python3
"""Compress pytest output: collapse passing tests, preserve failures + summary.

Reads PostToolUse JSON from stdin. Emits JSON
{"hookSpecificOutput": {"updatedToolOutput": "..."}} on stdout to replace
output, or exits 0 silently to pass through unchanged.

3-layer fail-open:
  1. Bash wrapper pre-filter (only pytest commands)
  2. Python double-checks tool_input.command (defense in depth)
  3. Sanity guards before replacement (FAILED/ERROR preservation)
"""

import json
import re
import sys

# Pyright stubs miss reconfigure, but it exists on Python 3.7+.
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # pyright: ignore[reportAttributeAccessIssue]
    except (OSError, AttributeError):
        pass

# Strip ANSI escape codes before regex matching.
# pytest --color=yes emits \x1b[31m===\x1b[0m — naive ^=+ misses.
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

# Section header on cleaned line: "==== test session starts ===="
SECTION_RE = re.compile(r"^=+\s+(.+?)\s+=+\s*$")

# Passing test file line: "tests/foo.py ........  [ 50%]"
# [\.\s]* matches dots+spaces. F/E/x letters break match → kept verbatim.
PASSING_RE = re.compile(r"^\S+\.py\s+[\.\s]*(\[\s*\d+%\])?\s*$")

# Word-boundary count for failure preservation check.
FAIL_TOKEN_RE = re.compile(r"\b(?:FAILED|ERROR)\b")

# Verify pytest in command (defense-in-depth vs bash pre-filter false positives).
PYTEST_CMD_RE = re.compile(r"\b(?:pytest|python\s+-m\s+pytest)\b")

MIN_LINES_TO_COMPRESS = 30
MIN_COMPRESSION_RATIO = 0.85
MIN_RESULT_LENGTH = 50


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError, OSError):
        sys.exit(0)

    # Defense-in-depth: re-verify pytest command in python.
    cmd = (data.get("tool_input") or {}).get("command", "")
    if not isinstance(cmd, str) or not PYTEST_CMD_RE.search(cmd):
        sys.exit(0)

    resp = data.get("tool_response") or {}
    stdout = resp.get("stdout") or ""
    stderr = resp.get("stderr") or ""
    combined = stdout + (("\n" + stderr) if stderr else "")

    if not combined:
        sys.exit(0)

    lines = combined.split("\n")
    if len(lines) < MIN_LINES_TO_COMPRESS:
        sys.exit(0)

    output = []
    section = "header"
    collapsed = 0

    def flush_collapsed():
        nonlocal collapsed
        if collapsed:
            output.append(f"  [...{collapsed} test files passing — collapsed]")
            collapsed = 0

    for line in lines:
        clean = ANSI_RE.sub("", line)  # for matching only
        match = SECTION_RE.match(clean)
        if match:
            flush_collapsed()
            title = match.group(1).lower()
            if "failure" in title or "error" in title:
                section = "failures"
            elif "session start" in title:
                section = "session"
            elif "summary" in title or "warning" in title or "passed" in title:
                section = "summary"
            else:
                section = "other"
            output.append(line)
            continue

        if section == "session" and PASSING_RE.match(clean):
            collapsed += 1
            continue

        # Everything else verbatim — failures, errors, tracebacks, summary.
        output.append(line)

    flush_collapsed()
    result = "\n".join(output)

    # Sanity 1: compression saved <15% → not worth replacing.
    if len(result) > len(combined) * MIN_COMPRESSION_RATIO:
        sys.exit(0)

    # Sanity 2: lost FAILED/ERROR markers → bug, fail open.
    if len(FAIL_TOKEN_RE.findall(combined)) != len(FAIL_TOKEN_RE.findall(result)):
        sys.exit(0)

    # Sanity 3: suspiciously short result → likely regex bug.
    if len(result.strip()) < MIN_RESULT_LENGTH:
        sys.exit(0)

    print(json.dumps({"hookSpecificOutput": {"updatedToolOutput": result}}))


if __name__ == "__main__":
    main()
