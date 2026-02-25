#!/bin/bash
# daily-report.sh - 通过 tmux + Claude CLI 交互模式自动生成每日日报
# Claude 交互模式自动加载 ~/.claude/.mcp.json，无需显式配置 MCP

set -euo pipefail

# 确保 PATH 包含 node/npx
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# 获取脚本所在目录，确保从任意位置执行都能正确定位项目路径
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 项目根目录（scripts 的上一级）
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# 运行配置文件
CONFIG_FILE="$PROJECT_DIR/config.json"
# 日报 Prompt 模板文件
PROMPT_FILE="$PROJECT_DIR/prompts/daily-report-prompt.prompt"
# tmux 执行器
TMUX_RUNNER="$SCRIPT_DIR/run-claude-tmux.sh"
# 日志目录与日志文件
LOG_DIR="$PROJECT_DIR/logs"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/daily-${TODAY}.log"

# 从配置中读取模型
CLAUDE_MODEL=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('model', 'sonnet'))
")

# 校验必须的文件
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: config.json not found at $CONFIG_FILE" >&2
  exit 1
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: Prompt template not found at $PROMPT_FILE" >&2
  exit 1
fi

if [ ! -x "$TMUX_RUNNER" ]; then
  echo "Error: tmux runner not found at $TMUX_RUNNER" >&2
  exit 1
fi

# 确保日志目录存在
mkdir -p "$LOG_DIR"

echo "[$TODAY] Starting daily report generation..." | tee -a "$LOG_FILE"

# Step 1: 收集当日 Git 提交日志
echo "[$TODAY] Gathering git commit logs..." | tee -a "$LOG_FILE"
GIT_LOGS=$("$SCRIPT_DIR/gather-git-logs.sh" 2>&1) || {
  echo "[$TODAY] Warning: Failed to gather git logs, continuing with empty logs" | tee -a "$LOG_FILE"
  GIT_LOGS="今日无代码提交记录"
}

# 记录本次收集到的 Git 日志
echo "[$TODAY] Git logs collected:" | tee -a "$LOG_FILE"
echo "$GIT_LOGS" | tee -a "$LOG_FILE"

# Step 2: 用 python3 替换模板占位符，写入临时文件（避免 shell 特殊字符问题）
echo "[$TODAY] Building prompt from template..." | tee -a "$LOG_FILE"
TEMP_PROMPT=$(mktemp /tmp/daily-prompt-XXXXXXXX)
TEMP_GIT_LOGS=$(mktemp /tmp/daily-gitlogs-XXXXXXXX)
trap "rm -f '$TEMP_PROMPT' '$TEMP_GIT_LOGS'" EXIT

# 将 git 日志写入临时文件，供 python3 读取
echo "$GIT_LOGS" > "$TEMP_GIT_LOGS"

python3 << PYEOF
with open('$PROMPT_FILE', 'r') as f:
    content = f.read()
with open('$TEMP_GIT_LOGS', 'r') as f:
    git_logs = f.read()
content = content.replace('{{GIT_LOGS}}', git_logs)
content = content.replace('{{TODAY_DATE}}', '$TODAY')
with open('$TEMP_PROMPT', 'w') as f:
    f.write(content)
PYEOF

# Step 3: 通过 tmux 交互模式调用 Claude 生成日报
echo "[$TODAY] Invoking Claude via tmux runner..." | tee -a "$LOG_FILE"
echo "[$TODAY] Model: $CLAUDE_MODEL" | tee -a "$LOG_FILE"

"$TMUX_RUNNER" "$TEMP_PROMPT" "$LOG_FILE" "$CLAUDE_MODEL" 25
EXIT_CODE=$?

# 根据退出码记录结果
if [ $EXIT_CODE -eq 0 ]; then
  echo "[$TODAY] Daily report generated successfully." | tee -a "$LOG_FILE"
else
  echo "[$TODAY] Error: tmux runner exited with code $EXIT_CODE" | tee -a "$LOG_FILE"
  exit $EXIT_CODE
fi
