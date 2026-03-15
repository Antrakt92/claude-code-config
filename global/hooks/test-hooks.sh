#!/bin/bash
# Test suite for global Claude Code hooks.
# Run: bash ~/.claude/hooks/test-hooks.sh
#
# Tests hook logic (command matching, file detection, double-fire prevention).
# Pre-commit auto-checks (ruff/tsc/pytest) NOT tested — they need real project state.
# Ripple check tested with temp files containing definitions.
#
# WHY >/dev/null 2>&1 on most tests: hooks output to stderr. We only care about exit codes.

PASS=0
FAIL=0

check() {
  local desc="$1"
  local expected_exit="$2"
  local actual_exit="$3"
  if [ "$actual_exit" = "$expected_exit" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected exit $expected_exit, got $actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"

# =============================================
echo "=== pre-commit-review.sh (command matching) ==="
# =============================================

# WHY: non-commit commands must pass through
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash "$HOOKS_DIR/pre-commit-review.sh" >/dev/null 2>&1
check "'git status' → allowed (not a commit)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"echo git commit"}}' | bash "$HOOKS_DIR/pre-commit-review.sh" >/dev/null 2>&1
check "'echo git commit' → allowed (not real commit)" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"grep git commit README"}}' | bash "$HOOKS_DIR/pre-commit-review.sh" >/dev/null 2>&1
check "'grep git commit' → allowed (not real commit)" 0 $?

# WHY: chained commit after another command should be detected
# WHY needs git repo with staged files: hook exits 0 on empty STAGED (nothing to review)
TMPCHAIN=$(mktemp -d)
(cd "$TMPCHAIN" && git init -q && git config user.email "test@test.com" && git config user.name "Test" && echo "hi" > file.txt && git add file.txt) >/dev/null 2>&1
echo '{"tool_name":"Bash","tool_input":{"command":"git add . && git commit -m test"}}' | (cd "$TMPCHAIN" && bash "$HOOKS_DIR/pre-commit-review.sh") >/dev/null 2>&1
check "'git add && git commit' → detected as commit" 2 $?
rm -rf "$TMPCHAIN"

# === Double-fire prevention ===
echo ""
echo "--- pre-commit-review.sh: double-fire prevention ---"

# WHY: create a temp project dir with a project-level hook to test skip logic
TMPPROJECT=$(mktemp -d)
mkdir -p "$TMPPROJECT/.claude/hooks"
touch "$TMPPROJECT/.claude/hooks/pre-commit-review.sh"
# WHY: also init git so git diff --cached doesn't error
(cd "$TMPPROJECT" && git init -q && git config user.email "test@test.com" && git config user.name "Test" && touch file.txt && git add file.txt) >/dev/null 2>&1

echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | (cd "$TMPPROJECT" && bash "$HOOKS_DIR/pre-commit-review.sh") >/dev/null 2>&1
check "git commit with project-level hook → skipped (double-fire)" 0 $?

rm -rf "$TMPPROJECT"

# === Marker bypass ===
echo ""
echo "--- pre-commit-review.sh: marker bypass ---"

TMPPROJECT2=$(mktemp -d)
(cd "$TMPPROJECT2" && git init -q && git config user.email "test@test.com" && git config user.name "Test" && echo "hello" > file.txt && git add file.txt) >/dev/null 2>&1
REPO_HASH=$(cd "$TMPPROJECT2" && pwd | cksum | cut -d' ' -f1)
MARKER="/tmp/claude-commit-reviewed-$REPO_HASH"

# Without marker — should block (Phase 2)
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | (cd "$TMPPROJECT2" && bash "$HOOKS_DIR/pre-commit-review.sh") >/dev/null 2>&1
check "git commit without marker → blocked (Phase 2)" 2 $?

# With marker — should allow
touch "$MARKER"
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | (cd "$TMPPROJECT2" && bash "$HOOKS_DIR/pre-commit-review.sh") >/dev/null 2>&1
check "git commit with marker → allowed" 0 $?

# Marker should be consumed (single-use)
echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m test"}}' | (cd "$TMPPROJECT2" && bash "$HOOKS_DIR/pre-commit-review.sh") >/dev/null 2>&1
check "git commit after marker consumed → blocked again" 2 $?

rm -rf "$TMPPROJECT2"
rm -f "$MARKER"

# =============================================
echo ""
echo "=== auto-lint-typescript.sh ==="
# =============================================

# WHY: non-TS files must be skipped
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/src/app.py"}}' | bash "$HOOKS_DIR/auto-lint-typescript.sh" >/dev/null 2>&1
check "Python file → skipped" 0 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/src/app.css"}}' | bash "$HOOKS_DIR/auto-lint-typescript.sh" >/dev/null 2>&1
check "CSS file → skipped" 0 $?

# WHY: .ts file with no eslint config anywhere → should skip (no config found)
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/no-eslint-project/src/app.ts"}}' | bash "$HOOKS_DIR/auto-lint-typescript.sh" >/dev/null 2>&1
check "TS file without eslint config → skipped" 0 $?

# === Double-fire prevention ===
echo ""
echo "--- auto-lint-typescript.sh: double-fire prevention ---"

TMPPROJECT3=$(mktemp -d)
mkdir -p "$TMPPROJECT3/.claude/hooks"
touch "$TMPPROJECT3/.claude/hooks/auto-lint-typescript.sh"

echo '{"tool_name":"Edit","tool_input":{"file_path":"'$TMPPROJECT3'/src/app.ts"}}' | (cd "$TMPPROJECT3" && bash "$HOOKS_DIR/auto-lint-typescript.sh") >/dev/null 2>&1
check "TS file with project-level hook → skipped (double-fire)" 0 $?

rm -rf "$TMPPROJECT3"

# =============================================
echo ""
echo "=== ripple-check.sh ==="
# =============================================

# WHY: non-code files must be skipped
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/README.md"}}' | bash "$HOOKS_DIR/ripple-check.sh" >/dev/null 2>&1
check "Markdown file → skipped" 0 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/config.json"}}' | bash "$HOOKS_DIR/ripple-check.sh" >/dev/null 2>&1
check "JSON file → skipped" 0 $?

# WHY: files in excluded dirs should be skipped
echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/node_modules/pkg/index.ts"}}' | bash "$HOOKS_DIR/ripple-check.sh" >/dev/null 2>&1
check "node_modules file → skipped" 0 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/dist/bundle.js"}}' | bash "$HOOKS_DIR/ripple-check.sh" >/dev/null 2>&1
check "dist/ file → skipped" 0 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/__pycache__/mod.py"}}' | bash "$HOOKS_DIR/ripple-check.sh" >/dev/null 2>&1
check "__pycache__ file → skipped" 0 $?

# WHY: nonexistent file should not crash
echo '{"tool_name":"Edit","tool_input":{"file_path":"/nonexistent/file.py"}}' | bash "$HOOKS_DIR/ripple-check.sh" >/dev/null 2>&1
check "Nonexistent file → skipped (no crash)" 0 $?

# WHY: always exit 0 — ripple check is non-blocking
# Test with a real temp file that has definitions
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/src"

cat > "$TMPDIR/src/utils.py" << 'PYEOF'
def calculate_total_tax(income, rate):
    return income * rate

class TaxCalculator:
    pass

CURRENCY_PRECISION = 2
PYEOF

# WHY: create a caller file so grep finds usages
cat > "$TMPDIR/src/service.py" << 'PYEOF'
from utils import calculate_total_tax, TaxCalculator

result = calculate_total_tax(1000, 0.33)
calc = TaxCalculator()
PYEOF

echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/src/utils.py\"}}" | (cd "$TMPDIR" && bash "$HOOKS_DIR/ripple-check.sh") >/dev/null 2>&1
check "Python file with callers → exit 0 (non-blocking)" 0 $?

# WHY: verify warnings are actually emitted to stderr
STDERR_OUT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/src/utils.py\"}}" | (cd "$TMPDIR" && bash "$HOOKS_DIR/ripple-check.sh") 2>&1 >/dev/null)
if echo "$STDERR_OUT" | grep -q "RIPPLE CHECK"; then
  echo "  PASS: ripple check emits warnings to stderr"
  PASS=$((PASS + 1))
else
  echo "  FAIL: ripple check should emit warnings for used definitions"
  FAIL=$((FAIL + 1))
fi

# WHY: verify calculate_total_tax is mentioned in the warning
if echo "$STDERR_OUT" | grep -q "calculate_total_tax"; then
  echo "  PASS: warning mentions calculate_total_tax"
  PASS=$((PASS + 1))
else
  echo "  FAIL: warning should mention calculate_total_tax"
  FAIL=$((FAIL + 1))
fi

# Test TypeScript definitions
cat > "$TMPDIR/src/types.ts" << 'TSEOF'
export interface HoldingRow {
  asset: string;
  value: number;
}

export function formatCurrency(amount: number): string {
  return amount.toFixed(2);
}

export const MAX_RETRIES = 3;
TSEOF

cat > "$TMPDIR/src/app.ts" << 'TSEOF'
import { HoldingRow, formatCurrency } from './types';

const row: HoldingRow = { asset: 'AAPL', value: 100 };
console.log(formatCurrency(row.value));
TSEOF

STDERR_TS=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/src/types.ts\"}}" | (cd "$TMPDIR" && bash "$HOOKS_DIR/ripple-check.sh") 2>&1 >/dev/null)
if echo "$STDERR_TS" | grep -q "RIPPLE CHECK"; then
  echo "  PASS: TS ripple check emits warnings"
  PASS=$((PASS + 1))
else
  echo "  FAIL: TS ripple check should emit warnings for used exports"
  FAIL=$((FAIL + 1))
fi

# Test file with no external usages — should emit no warnings
cat > "$TMPDIR/src/isolated.py" << 'PYEOF'
def very_unique_isolated_function_xyz():
    pass
PYEOF

STDERR_NONE=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/src/isolated.py\"}}" | (cd "$TMPDIR" && bash "$HOOKS_DIR/ripple-check.sh") 2>&1 >/dev/null)
if [ -z "$STDERR_NONE" ]; then
  echo "  PASS: no warnings for unused definitions"
  PASS=$((PASS + 1))
else
  echo "  FAIL: should not warn for definitions with no callers"
  FAIL=$((FAIL + 1))
fi

# WHY: short names (<4 chars) should be filtered out to avoid noise
cat > "$TMPDIR/src/short.py" << 'PYEOF'
def get():
    pass

def run():
    pass

def id():
    pass
PYEOF

cat > "$TMPDIR/src/caller_short.py" << 'PYEOF'
from short import get, run, id
get()
PYEOF

STDERR_SHORT=$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$TMPDIR/src/short.py\"}}" | (cd "$TMPDIR" && bash "$HOOKS_DIR/ripple-check.sh") 2>&1 >/dev/null)
if [ -z "$STDERR_SHORT" ]; then
  echo "  PASS: short names (<4 chars) filtered out"
  PASS=$((PASS + 1))
else
  echo "  FAIL: short names should be filtered out (got: $STDERR_SHORT)"
  FAIL=$((FAIL + 1))
fi

rm -rf "$TMPDIR"

# =============================================
echo ""
echo "=== block-dangerous-git.sh (existing tests) ==="
# =============================================

echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "git push --force → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "git push --force-with-lease → allowed" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git reset --hard HEAD~1"}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "git reset --hard → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git checkout ."}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "git checkout . → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"git checkout main"}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "git checkout main → allowed" 0 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf backend/"}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "rm -rf backend/ → blocked" 2 $?

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf node_modules/"}}' | bash "$HOOKS_DIR/block-dangerous-git.sh" >/dev/null 2>&1
check "rm -rf node_modules/ → allowed (whitelisted)" 0 $?

# =============================================
echo ""
echo "=== block-protected-files.sh (spot checks) ==="
# =============================================

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/.env"}}' | bash "$HOOKS_DIR/block-protected-files.sh" >/dev/null 2>&1
check "Edit .env → blocked" 2 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/.env.example"}}' | bash "$HOOKS_DIR/block-protected-files.sh" >/dev/null 2>&1
check "Edit .env.example → allowed" 0 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/package-lock.json"}}' | bash "$HOOKS_DIR/block-protected-files.sh" >/dev/null 2>&1
check "Edit package-lock.json → blocked" 2 $?

echo '{"tool_name":"Edit","tool_input":{"file_path":"/project/src/app.ts"}}' | bash "$HOOKS_DIR/block-protected-files.sh" >/dev/null 2>&1
check "Edit app.ts → allowed" 0 $?

# =============================================
echo ""
echo "========================================="
echo "  Passed: $PASS / $((PASS + FAIL))"
if [ "$FAIL" -gt 0 ]; then
  echo "  FAILED: $FAIL"
  echo "========================================="
  exit 1
else
  echo "  ALL TESTS PASSED"
  echo "========================================="
fi
