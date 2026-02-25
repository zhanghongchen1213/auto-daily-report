#!/bin/bash
# weekly-report.sh - 通过 tmux + Claude CLI 交互模式汇总日报生成周报
# Claude 交互模式自动加载 ~/.claude/.mcp.json，无需显式配置 MCP
set -euo pipefail

# 确保 PATH 包含 node/npx
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# 定位脚本目录与项目根目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# 配置文件
CONFIG_FILE="$PROJECT_DIR/config.json"
# 周报 Prompt 模板
PROMPT_FILE="${PROJECT_DIR}/prompts/weekly-report-prompt.prompt"
# tmux 执行器
TMUX_RUNNER="$SCRIPT_DIR/run-claude-tmux.sh"
# 日志目录
LOG_DIR="${PROJECT_DIR}/logs"

# 校验配置文件
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: config.json not found at $CONFIG_FILE" >&2
    exit 1
fi

# 从配置中读取模型
CLAUDE_MODEL=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('model', 'sonnet'))
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

# 校验 tmux 执行器是否可用
if [[ ! -x "$TMUX_RUNNER" ]]; then
    echo "ERROR: tmux runner not found or not executable: $TMUX_RUNNER" | tee -a "$LOG_FILE"
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

echo "Invoking Claude via tmux runner..." | tee -a "$LOG_FILE"
echo "Model: $CLAUDE_MODEL" | tee -a "$LOG_FILE"

"$TMUX_RUNNER" "$TEMP_PROMPT" "$LOG_FILE" "$CLAUDE_MODEL" 25
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Weekly report generated successfully." | tee -a "$LOG_FILE"
else
    echo "" | tee -a "$LOG_FILE"
    echo "ERROR: tmux runner exited with code $EXIT_CODE" | tee -a "$LOG_FILE"
    exit $EXIT_CODE
fi

echo "Log saved to: $LOG_FILE"
