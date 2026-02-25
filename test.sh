#!/bin/bash
# test.sh - System checks for the auto-report system
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

# 1. Config validation
echo "[1/8] Config validation"
test -f "$SCRIPT_DIR/config.json"
check "config.json exists" $?

python3 -c "import json; json.load(open('$SCRIPT_DIR/config.json'))" 2>/dev/null
check "config.json is valid JSON" $?

# 2. Script files exist and are executable
echo "[2/8] Script files"
for script in run-claude-tmux.sh gather-git-logs.sh; do
  test -x "$SCRIPT_DIR/scripts/$script" 2>/dev/null
  check "$script is executable" $?
done

# 3. Skill files exist
echo "[3/8] Skill files"
for skill in daily-report.md weekly-report.md monthly-report.md; do
  test -f "$SCRIPT_DIR/.claude/skills/$skill"
  check "skill $skill exists" $?
done

# 4. Launchd plist syntax validation
echo "[4/8] Launchd plist validation"
for plist in com.auto-report.daily.plist com.auto-report.weekly.plist com.auto-report.monthly.plist; do
  plutil -lint "$SCRIPT_DIR/launchd/$plist" >/dev/null 2>&1
  check "$plist syntax valid" $?
done

# 5. Claude CLI accessible
echo "[5/8] Claude CLI"
CLAUDE_CLI=$(python3 -c "
import json
with open('$SCRIPT_DIR/config.json') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")
test -x "$CLAUDE_CLI" 2>/dev/null || command -v "$CLAUDE_CLI" >/dev/null 2>&1
check "Claude CLI accessible at $CLAUDE_CLI" $?

# 6. tmux available
echo "[6/8] tmux"
command -v tmux >/dev/null 2>&1
check "tmux is installed" $?

# 7. Git log gathering
echo "[7/8] Git log gathering"
OUTPUT=$("$SCRIPT_DIR/scripts/gather-git-logs.sh" 2>&1) || true
test -n "$OUTPUT"
check "gather-git-logs.sh produces output" $?

# 8. run-claude-tmux.sh argument validation
echo "[8/8] run-claude-tmux.sh smoke test"
# Verify the script can be parsed by bash without syntax errors
bash -n "$SCRIPT_DIR/scripts/run-claude-tmux.sh" 2>/dev/null
check "run-claude-tmux.sh has valid bash syntax" $?

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && green "All tests passed!" || red "Some tests failed."
exit $FAIL
