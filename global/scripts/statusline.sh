#!/bin/bash
# Thin wrapper — settings.json calls this, this exec's python.
# WHY: ~ expansion + portable path resolution on Windows git bash.
exec python "$(dirname "$0")/statusline.py"
