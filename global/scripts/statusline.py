#!/usr/bin/env python3
"""Claude Code statusline — detailed view.

Reads session JSON from stdin, prints one line.
Fail-open: missing field → silent skip, never crashes.
Schema ref: docs.claude.com + github.com/anthropics/claude-code/issues/13158
"""

import json
import os
import re
import subprocess
import sys

# UTF-8 stdout — Windows default cp1252 crashes on emoji.
# Pyright stubs miss reconfigure, but it exists on Python 3.7+.
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # pyright: ignore[reportAttributeAccessIssue]
    except (OSError, AttributeError):
        pass

DEBUG_DUMP_CAP = 50 * 1024
DEBUG_DUMP_PATH = os.path.expanduser("~/.claude/statusline-debug.json")
BRANCH_TRUNCATE = 30

# "claude-MODELID-DATE" suffix: 8+ digits at end.
MODEL_ID_DATE_SUFFIX = re.compile(r"-\d{8,}$")


def main():
    raw = sys.stdin.read()

    # STATUSLINE_DEBUG=1 → dump capped raw stdin for schema diagnosis.
    if os.environ.get("STATUSLINE_DEBUG") == "1":
        try:
            with open(DEBUG_DUMP_PATH, "w", encoding="utf-8") as f:
                f.write(raw[:DEBUG_DUMP_CAP])
        except OSError:
            pass

    try:
        data = json.loads(raw) if raw else {}
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    model_obj = data.get("model") or {}
    model = _shorten_model(
        model_obj.get("display_name") or model_obj.get("id") or "claude"
    )
    effort = model_obj.get("reasoning_effort") or ""
    thinking = "🧠" if model_obj.get("thinking_enabled") else ""

    ctx = data.get("context_window") or {}
    pct = ctx.get("used_percentage")
    # bool is int subtype — exclude True/False.
    ctx_str = (
        f"📊 {int(pct)}%"
        if isinstance(pct, (int, float)) and not isinstance(pct, bool)
        else ""
    )

    workspace = data.get("workspace") or {}
    cwd = workspace.get("current_dir") or data.get("cwd") or ""
    cwd_name = os.path.basename(cwd.rstrip("/\\")) if cwd else ""

    segments = [f"🤖 {model}"]
    if effort:
        segments.append(effort)
    if thinking:
        segments.append(thinking)
    if ctx_str:
        segments.append(ctx_str)
    if cwd_name:
        segments.append(f"📁 {cwd_name}")

    git_segment = _git_info(cwd) if cwd and os.path.isdir(cwd) else ""

    line = "  ".join(segments) + git_segment
    sys.stdout.write(line)


def _shorten_model(name):
    """'claude-opus-4-7-20251101' → 'opus-4-7'.
    'Opus 4.7' → 'Opus 4.7' (display names pass through).
    'claude-opus-4-7' → 'opus-4-7' (strip prefix even without date suffix).
    """
    if not isinstance(name, str):
        return "claude"
    if name.startswith("claude-"):
        name = name[len("claude-") :]
        name = MODEL_ID_DATE_SUFFIX.sub("", name)
    return name or "claude"


def _git_info(cwd):
    """Return '   <branch> ●<dirty_count>' or empty string on any failure."""
    try:
        branch = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        ).stdout.strip()
        if not branch or branch == "HEAD":
            return ""
        if len(branch) > BRANCH_TRUNCATE:
            branch = branch[: BRANCH_TRUNCATE - 3] + "..."

        status_out = subprocess.run(
            ["git", "-C", cwd, "status", "--porcelain", "-uno"],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        ).stdout
        n_dirty = sum(1 for ln in status_out.split("\n") if ln.strip())
        dirty = f" ●{n_dirty}" if n_dirty else ""

        return f"   {branch}{dirty}"
    except (subprocess.SubprocessError, OSError):
        return ""


if __name__ == "__main__":
    main()
