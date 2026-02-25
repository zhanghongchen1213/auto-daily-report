#!/bin/bash
# test.sh - Dry-run tests for the auto-report system
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

check() {
  local desc="$1" result="$2"
  if [ "$result" = "0" ]; then
    green "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Auto Report System Tests ==="
echo ""

# 1. Config file
echo "[1/6] Config validation"
test -f "$SCRIPT_DIR/config.json"
check "config.json exists" $?

python3 -c "import json; json.load(open('$SCRIPT_DIR/config.json'))" 2>/dev/null
check "config.json is valid JSON" $?

# 2. Script files exist and are executable
echo "[2/6] Script files"
for script in gather-git-logs.sh daily-report.sh weekly-report.sh monthly-report.sh; do
  test -x "$SCRIPT_DIR/scripts/$script" 2>/dev/null
  check "$script is executable" $?
done

# 3. Prompt templates exist
echo "[3/6] Prompt templates"
for prompt in daily-report-prompt.prompt weekly-report-prompt.prompt monthly-report-prompt.prompt; do
  test -f "$SCRIPT_DIR/prompts/$prompt"
  check "$prompt exists" $?
done

# 4. Launchd plists syntax
echo "[4/6] Launchd plist validation"
for plist in com.auto-report.daily.plist com.auto-report.weekly.plist com.auto-report.monthly.plist; do
  plutil -lint "$SCRIPT_DIR/launchd/$plist" >/dev/null 2>&1
  check "$plist syntax valid" $?
done

# 5. Claude CLI available
echo "[5/6] Claude CLI"
CLAUDE_CLI=$(python3 -c "
import json
with open('$SCRIPT_DIR/config.json') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")
test -x "$CLAUDE_CLI" 2>/dev/null || command -v "$CLAUDE_CLI" >/dev/null 2>&1
check "Claude CLI accessible at $CLAUDE_CLI" $?

# 6. Git log gathering
echo "[6/6] Git log gathering"
OUTPUT=$("$SCRIPT_DIR/scripts/gather-git-logs.sh" 2>&1) || true
test -n "$OUTPUT"
check "gather-git-logs.sh produces output" $?

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && green "All tests passed!" || red "Some tests failed."
exit $FAIL
