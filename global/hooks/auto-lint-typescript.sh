#!/bin/bash
# PostToolUse hook: auto-lint TypeScript files with ESLint after Edit/Write.
#
# WHY: AI writes code → ESLint reformats → AI's old_string in next Edit won't match.
# Exit 2 + stderr forces AI to re-read the file before next Edit.
#
# DOUBLE-FIRE PREVENTION: if project-level .claude/hooks/auto-lint-typescript.sh exists,
# this hook exits 0 immediately — the project hook takes precedence.
# WHY: both global and project hooks fire on the same event. Without this guard,
# TS files in projects with custom auto-lint hooks get linted twice.
#
# SYNC WITH: auto-lint-python.sh (same md5sum/exit 2 pattern)
# SYNC WITH: CLAUDE.md §9 Global Hooks

INPUT=$(cat)

# --- Double-fire prevention ---
if [ -f ".claude/hooks/auto-lint-typescript.sh" ]; then
  exit 0
fi

# SYNC WITH: all hooks use identical JSON extraction — change one, change all.
# WHY ([^"\\]|\\.)*: escape-aware JSON extraction, handles \" and \\ in values.
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//' | sed 's/\\"/"/g; s/\\\\/\\/g')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

if [[ "$FILE_PATH" != *.ts ]] && [[ "$FILE_PATH" != *.tsx ]]; then
  exit 0
fi

# WHY: find ESLint config by walking up the directory tree from the file.
# Global hook can't assume "frontend/" — different projects have different structures.
# We need to find the nearest directory containing an eslint config.
ESLINT_DIR=""
SEARCH_DIR=$(dirname "$FILE_PATH")

# WHY limit to 10 levels: prevent infinite loop on broken symlinks or deep paths.
# Most projects have eslint config within 5 levels of source files.
LEVEL=0
while [ "$LEVEL" -lt 10 ] && [ "$SEARCH_DIR" != "/" ] && [ "$SEARCH_DIR" != "." ]; do
  # WHY check multiple config formats: ESLint 8 uses .eslintrc*, ESLint 9 uses eslint.config.*
  for cfg in "$SEARCH_DIR/eslint.config."* "$SEARCH_DIR/.eslintrc"* "$SEARCH_DIR/.eslintrc.json" "$SEARCH_DIR/.eslintrc.js" "$SEARCH_DIR/.eslintrc.yml"; do
    if [ -f "$cfg" ]; then
      ESLINT_DIR="$SEARCH_DIR"
      break 2
    fi
  done
  # WHY also check package.json with eslintConfig key: some projects inline their ESLint config
  if [ -f "$SEARCH_DIR/package.json" ] && grep -q '"eslintConfig"' "$SEARCH_DIR/package.json" 2>/dev/null; then
    ESLINT_DIR="$SEARCH_DIR"
    break
  fi
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
  LEVEL=$((LEVEL + 1))
done

if [ -z "$ESLINT_DIR" ]; then
  exit 0
fi

BEFORE=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

# WHY cd subshell: ESLint needs config-relative CWD. FILE_PATH is absolute, so resolves fine.
# WHY || true: ESLint exits non-zero for unfixable issues; we still check if file changed.
(cd "$ESLINT_DIR" && npx eslint --fix "$FILE_PATH") >/dev/null 2>&1 || true
AFTER=$(md5sum "$FILE_PATH" 2>/dev/null | cut -d' ' -f1)

if [ "$BEFORE" != "$AFTER" ]; then
  echo "AUTO-LINT: ESLint reformatted $(basename "$FILE_PATH") — re-read before next edit." >&2
  exit 2
fi

exit 0
