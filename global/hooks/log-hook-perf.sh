#!/bin/bash
# PostToolUse hook: log tool duration_ms to ~/.claude/hook-perf.log.
exec python "$(dirname "$0")/log-hook-perf.py"
