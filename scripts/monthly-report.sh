#!/bin/bash
# monthly-report.sh - 通过 Claude + Notion MCP 汇总周报生成月报
# 读取当月周报并生成完整月度总结

set -euo pipefail

# 定位脚本目录与项目根目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# 配置与模板路径
CONFIG_FILE="$PROJECT_DIR/config.json"
PROMPT_FILE="$PROJECT_DIR/prompts/monthly-report-prompt.prompt"
# 日志目录
LOG_DIR="$PROJECT_DIR/logs"

# 校验必须的配置与模板文件
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config.json not found at $CONFIG_FILE" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: monthly-report-prompt.prompt not found at $PROMPT_FILE" >&2
  exit 1
fi

# 从配置中读取 Claude CLI 路径
CLAUDE_CLI=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")

# Claude CLI 必须可执行
if [ ! -x "$CLAUDE_CLI" ]; then
  echo "Error: Claude CLI not found or not executable at $CLAUDE_CLI" >&2
  exit 1
fi

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 计算当月起止日期
MONTH_YEAR=$(date +%Y)
MONTH_NUM=$(date +%-m)
MONTH_START=$(date +%Y-%m-01)
# Last day of current month: go to next month's 1st, subtract 1 day
MONTH_END=$(date -v+1m -v1d -v-1d +%Y-%m-%d)

LOG_FILE="$LOG_DIR/monthly-$(date +%Y-%m).log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monthly report generation started" | tee -a "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Period: $MONTH_START to $MONTH_END" | tee -a "$LOG_FILE"

# 判断今天是否为当月最后一个工作日（周末向前顺延）
is_last_working_day() {
  local today=$(date +%Y-%m-%d)
  local last_day="$MONTH_END"
  local last_day_dow=$(date -j -f "%Y-%m-%d" "$last_day" +%u 2>/dev/null)

  # Find the last working day (Mon-Fri)
  local last_work_day="$last_day"
  if [ "$last_day_dow" -eq 6 ]; then
    # Saturday -> Friday
    last_work_day=$(date -j -f "%Y-%m-%d" -v-1d "$last_day" +%Y-%m-%d)
  elif [ "$last_day_dow" -eq 7 ]; then
    # Sunday -> Friday
    last_work_day=$(date -j -f "%Y-%m-%d" -v-2d "$last_day" +%Y-%m-%d)
  fi

  [ "$today" = "$last_work_day" ]
}

# --force 允许绕过最后工作日限制
FORCE=false
if [ "${1:-}" = "--force" ]; then
  FORCE=true
fi

# 非最后工作日且未强制，则跳过生成
if [ "$FORCE" = false ] && ! is_last_working_day; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Today is not the last working day of the month. Skipping." | tee -a "$LOG_FILE"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Use --force to generate anyway." | tee -a "$LOG_FILE"
  exit 0
fi

# 用 python3 替换模板占位符，写入临时文件（避免 shell 特殊字符问题）
TEMP_PROMPT=$(mktemp /tmp/monthly-prompt-XXXXXXXX)
trap "rm -f '$TEMP_PROMPT'" EXIT

python3 << PYEOF
with open('$PROMPT_FILE', 'r') as f:
    content = f.read()
content = content.replace('{{MONTH_START}}', '$MONTH_START')
content = content.replace('{{MONTH_END}}', '$MONTH_END')
content = content.replace('{{MONTH_YEAR}}', '$MONTH_YEAR')
content = content.replace('{{MONTH_NUM}}', '$MONTH_NUM')
with open('$TEMP_PROMPT', 'w') as f:
    f.write(content)
PYEOF

# 调用 Claude 生成月报（通过 stdin 管道传递 prompt）
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Invoking Claude CLI for monthly report generation..." | tee -a "$LOG_FILE"

cat "$TEMP_PROMPT" | "$CLAUDE_CLI" -p \
  --allowedTools "mcp__notion__*" \
  2>&1 | tee -a "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[1]}

if [ $EXIT_CODE -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monthly report generation completed successfully" | tee -a "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Error: Claude CLI exited with code $EXIT_CODE" | tee -a "$LOG_FILE"
  exit $EXIT_CODE
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log saved to $LOG_FILE" | tee -a "$LOG_FILE"
