#!/bin/bash
# weekly-report.sh - 通过 Claude + Notion MCP 汇总日报生成周报
set -euo pipefail

# 定位脚本目录与项目根目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# 配置文件
CONFIG_FILE="$PROJECT_DIR/config.json"
# 周报 Prompt 模板
PROMPT_FILE="${PROJECT_DIR}/prompts/weekly-report-prompt.prompt"
# 日志目录
LOG_DIR="${PROJECT_DIR}/logs"

# 校验配置文件
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config.json not found at $CONFIG_FILE" >&2
    exit 1
fi

# 从配置中读取 Claude CLI 路径
CLAUDE_CLI=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")

# 确保日志目录存在
mkdir -p "$LOG_DIR"

# 计算过去 7 天的时间范围（包含今天）
if [[ "$(uname)" == "Darwin" ]]; then
    WEEK_END=$(date -v-0d +%Y-%m-%d)
    WEEK_START=$(date -v-6d +%Y-%m-%d)
    WEEK_NUMBER=$(date +%V)
    WEEK_START_YEAR=$(date -j -f "%Y-%m-%d" "$WEEK_START" +%Y)
    WEEK_START_MMDD=$(date -j -f "%Y-%m-%d" "$WEEK_START" +%m.%d)
    WEEK_END_MMDD=$(date -j -f "%Y-%m-%d" "$WEEK_END" +%m.%d)
else
    WEEK_END=$(date +%Y-%m-%d)
    WEEK_START=$(date -d "6 days ago" +%Y-%m-%d)
    WEEK_NUMBER=$(date +%V)
    WEEK_START_YEAR=$(date -d "$WEEK_START" +%Y)
    WEEK_START_MMDD=$(date -d "$WEEK_START" +%m.%d)
    WEEK_END_MMDD=$(date -d "$WEEK_END" +%m.%d)
fi

# 日志文件按周编号保存
LOG_FILE="${LOG_DIR}/weekly-${WEEK_START_YEAR}-W${WEEK_NUMBER}.log"

echo "========================================" | tee -a "$LOG_FILE"
echo "Weekly Report Generation" | tee -a "$LOG_FILE"
echo "Period: ${WEEK_START} ~ ${WEEK_END} (W${WEEK_NUMBER})" | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 校验周报模板是否存在
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "ERROR: Prompt template not found: $PROMPT_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

# 校验 Claude CLI 是否可执行
if [[ ! -x "$CLAUDE_CLI" ]]; then
    echo "ERROR: Claude CLI not found or not executable: $CLAUDE_CLI" | tee -a "$LOG_FILE"
    exit 1
fi

# 用 python3 替换模板占位符，写入临时文件（避免 shell 特殊字符问题）
TEMP_PROMPT=$(mktemp /tmp/weekly-prompt-XXXXXXXX)
trap "rm -f '$TEMP_PROMPT'" EXIT

python3 << PYEOF
with open('$PROMPT_FILE', 'r') as f:
    content = f.read()
content = content.replace('{{WEEK_START}}', '$WEEK_START')
content = content.replace('{{WEEK_END}}', '$WEEK_END')
content = content.replace('{{WEEK_NUMBER}}', '$WEEK_NUMBER')
content = content.replace('{{WEEK_START_YEAR}}', '$WEEK_START_YEAR')
content = content.replace('{{WEEK_START_MMDD}}', '$WEEK_START_MMDD')
content = content.replace('{{WEEK_END_MMDD}}', '$WEEK_END_MMDD')
with open('$TEMP_PROMPT', 'w') as f:
    f.write(content)
PYEOF

echo "Invoking Claude CLI to generate weekly report..." | tee -a "$LOG_FILE"

# 通过 stdin 管道调用 Claude CLI（避免命令行参数过大或特殊字符问题）
cat "$TEMP_PROMPT" | "$CLAUDE_CLI" -p \
  --allowedTools "mcp__notion__*" \
  2>&1 | tee -a "$LOG_FILE"

EXIT_CODE=${PIPESTATUS[1]}

if [ $EXIT_CODE -eq 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Weekly report generated successfully." | tee -a "$LOG_FILE"
else
    echo "" | tee -a "$LOG_FILE"
    echo "ERROR: Claude CLI exited with code $EXIT_CODE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

echo "Log saved to: $LOG_FILE"
