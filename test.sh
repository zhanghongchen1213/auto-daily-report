#!/bin/bash
# test.sh - 将 config.json 中的数据库 ID 同步到 skill 模板
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
SKILLS_DIR="$SCRIPT_DIR/.claude/skills"

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

# 读取 config.json
if [ ! -f "$CONFIG" ]; then
  red "错误: config.json 不存在" && exit 1
fi

if command -v jq &>/dev/null; then
  read_cfg() { jq -r "$1" "$CONFIG"; }
else
  read_cfg() { python3 -c "import json; print(json.load(open('$CONFIG'))$(echo "$1" | sed "s/\./']['/g; s/^/['/; s/$/']/" ))"; }
fi

ACTIVITY_LOGS_DB_ID=$(read_cfg '.notion.databases.activity_logs')
DAILY_REPORT_DB_ID=$(read_cfg '.notion.databases.daily_report')
WEEKLY_REPORT_DB_ID=$(read_cfg '.notion.databases.weekly_report')
MONTHLY_REPORT_DB_ID=$(read_cfg '.notion.databases.monthly_report')

# 同步模板 → SKILL.md
ok=0 fail=0
for skill in daily-report weekly-report monthly-report; do
  tpl="$SKILLS_DIR/$skill/SKILL.md.tpl"
  out="$SKILLS_DIR/$skill/SKILL.md"

  if [ ! -f "$tpl" ]; then
    red "模板不存在: $tpl" && fail=$((fail + 1)) && continue
  fi

  sed \
    -e "s|{{PROJECT_DIR}}|$SCRIPT_DIR|g" \
    -e "s|{{ACTIVITY_LOGS_DB_ID}}|$ACTIVITY_LOGS_DB_ID|g" \
    -e "s|{{DAILY_REPORT_DB_ID}}|$DAILY_REPORT_DB_ID|g" \
    -e "s|{{WEEKLY_REPORT_DB_ID}}|$WEEKLY_REPORT_DB_ID|g" \
    -e "s|{{MONTHLY_REPORT_DB_ID}}|$MONTHLY_REPORT_DB_ID|g" \
    "$tpl" > "$out"

  ok=$((ok + 1))
done

echo "同步完成: $ok 成功, $fail 失败"
[ "$fail" -eq 0 ] && green "全部同步成功!" || { red "部分同步失败"; exit 1; }
