#!/bin/bash
# PostToolUse hook: section-aware pytest output compression.
#
# WHY bash pre-filter: most Bash tool calls are NOT pytest. Skip python startup
# (~80ms) for non-pytest commands. Pre-filter костит ~5ms.
# WHY printf: echo может портить backslash-sequences в input.
# WHY $(dirname "$0"): относительный путь к .py — единый source of truth.

INPUT=$(cat)

# Conservative pre-filter: command field must contain plausible pytest invocation.
# WHY \b: prevents matching "snippet contains pytest" false positives.
# Python double-checks tool_input.command before compressing — defense in depth.
if ! echo "$INPUT" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]*\b(pytest|python[[:space:]]+-m[[:space:]]+pytest)\b'; then
  exit 0
fi

printf '%s' "$INPUT" | exec python "$(dirname "$0")/compress-pytest-output.py"
