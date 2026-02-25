#!/bin/bash
# test.sh - 自动报告系统检查与配置同步
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }

check() {
  local desc="$1" result="$2"
  if [ "$result" = "0" ]; then
    green "  通过: $desc"
    PASS=$((PASS + 1))
  else
    red "  失败: $desc"
    FAIL=$((FAIL + 1))
  fi
}

# ── 配置同步函数 ──
sync_config() {
  local config="$SCRIPT_DIR/config.json"
  if [ ! -f "$config" ]; then
    red "  配置文件 config.json 不存在，跳过同步"
    return 1
  fi

  # 解析 config.json（优先 jq，回退 python3）
  if command -v jq &>/dev/null; then
    ACTIVITY_LOGS_DB_ID=$(jq -r '.notion.databases.activity_logs' "$config")
    DAILY_REPORT_DB_ID=$(jq -r '.notion.databases.daily_report' "$config")
    WEEKLY_REPORT_DB_ID=$(jq -r '.notion.databases.weekly_report' "$config")
    MONTHLY_REPORT_DB_ID=$(jq -r '.notion.databases.monthly_report' "$config")
  else
    eval "$(python3 -c "
import json
with open('$config') as f:
    c = json.load(f)
db = c['notion']['databases']
print(f'ACTIVITY_LOGS_DB_ID={db[\"activity_logs\"]}')
print(f'DAILY_REPORT_DB_ID={db[\"daily_report\"]}')
print(f'WEEKLY_REPORT_DB_ID={db[\"weekly_report\"]}')
print(f'MONTHLY_REPORT_DB_ID={db[\"monthly_report\"]}')
")"
  fi

  local project_dir="$SCRIPT_DIR"
  local skills_dir="$SCRIPT_DIR/.claude/skills"
  local sync_ok=0
  local sync_fail=0

  for skill in daily-report weekly-report monthly-report; do
    local tpl="$skills_dir/$skill/SKILL.md.tpl"
    local out="$skills_dir/$skill/SKILL.md"
    if [ ! -f "$tpl" ]; then
      red "  模板文件不存在: $tpl"
      sync_fail=$((sync_fail + 1))
      continue
    fi
    sed \
      -e "s|{{PROJECT_DIR}}|$project_dir|g" \
      -e "s|{{ACTIVITY_LOGS_DB_ID}}|$ACTIVITY_LOGS_DB_ID|g" \
      -e "s|{{DAILY_REPORT_DB_ID}}|$DAILY_REPORT_DB_ID|g" \
      -e "s|{{WEEKLY_REPORT_DB_ID}}|$WEEKLY_REPORT_DB_ID|g" \
      -e "s|{{MONTHLY_REPORT_DB_ID}}|$MONTHLY_REPORT_DB_ID|g" \
      "$tpl" > "$out"
    sync_ok=$((sync_ok + 1))
  done

  if [ "$sync_fail" -eq 0 ]; then
    green "  同步完成: ${sync_ok} 个 skill 文件已更新"
  else
    red "  同步部分失败: ${sync_ok} 成功, ${sync_fail} 失败"
  fi
  return $sync_fail
}

echo "=== 自动报告系统检查 ==="
echo ""

# 0. 配置同步
echo "[0/9] 配置同步"
sync_config
check "config → skill 同步" $?

# 1. 配置文件验证
echo "[1/9] 配置文件验证"
test -f "$SCRIPT_DIR/config.json"
check "config.json 存在" $?

python3 -c "import json; json.load(open('$SCRIPT_DIR/config.json'))" 2>/dev/null
check "config.json 格式有效" $?

# 2. 脚本文件检查
echo "[2/9] 脚本文件"
for script in run-claude-tmux.sh gather-git-logs.sh; do
  test -x "$SCRIPT_DIR/scripts/$script" 2>/dev/null
  check "$script 可执行" $?
done

# 3. Skill 文件检查
echo "[3/9] Skill 文件"
for skill in daily-report weekly-report monthly-report; do
  test -f "$SCRIPT_DIR/.claude/skills/$skill/SKILL.md"
  check "skill $skill/SKILL.md 存在" $?
  test -f "$SCRIPT_DIR/.claude/skills/$skill/SKILL.md.tpl"
  check "模板 $skill/SKILL.md.tpl 存在" $?
done

# 4. Launchd plist 语法验证
echo "[4/9] Launchd plist 验证"
for plist in com.auto-report.daily.plist com.auto-report.weekly.plist com.auto-report.monthly.plist; do
  plutil -lint "$SCRIPT_DIR/launchd/$plist" >/dev/null 2>&1
  check "$plist 语法有效" $?
done

# 5. Claude CLI 检查
echo "[5/9] Claude CLI"
CLAUDE_CLI=$(python3 -c "
import json
with open('$SCRIPT_DIR/config.json') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")
test -x "$CLAUDE_CLI" 2>/dev/null || command -v "$CLAUDE_CLI" >/dev/null 2>&1
check "Claude CLI 可访问 ($CLAUDE_CLI)" $?

# 6. tmux 检查
echo "[6/9] tmux"
command -v tmux >/dev/null 2>&1
check "tmux 已安装" $?

# 7. Git 日志收集
echo "[7/9] Git 日志收集"
OUTPUT=$("$SCRIPT_DIR/scripts/gather-git-logs.sh" 2>&1) || true
test -n "$OUTPUT"
check "gather-git-logs.sh 有输出" $?

# 8. run-claude-tmux.sh 语法检查
echo "[8/9] run-claude-tmux.sh 冒烟测试"
bash -n "$SCRIPT_DIR/scripts/run-claude-tmux.sh" 2>/dev/null
check "run-claude-tmux.sh 语法有效" $?

echo ""
echo "结果: $PASS 通过, $FAIL 失败"
[ "$FAIL" -eq 0 ] && green "全部检查通过!" || red "部分检查失败。"
exit $FAIL
