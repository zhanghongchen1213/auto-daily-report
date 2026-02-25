#!/bin/bash
# run-claude-tmux.sh - 启动可视化终端运行 Claude CLI 并执行指定 skill
# 用法: run-claude-tmux.sh <skill-name> [log-file]
#
# 流程：tmux 会话 → iTerm 可视化窗口 → Claude 交互模式 → 发送 skill 命令 → 等待1小时 → 关闭

set -euo pipefail

# ── 参数解析 ──
SKILL_NAME="${1:?Usage: run-claude-tmux.sh <skill-name> [log-file]}"
LOG_FILE="${2:-}"

# ── 配置 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.json"

# 从 config.json 读取 Claude CLI 路径和模型
CLAUDE_CLI=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")

CLAUDE_MODEL=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('model', 'sonnet'))
")

# 默认日志路径
if [ -z "$LOG_FILE" ]; then
  LOG_DIR="$PROJECT_DIR/logs"
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/${SKILL_NAME}-$(date +%Y%m%d).log"
fi

SESSION_NAME="claude-report-$(date +%s)"
WAIT_TIME=3600

# ── 前置检查 ──
for cmd in tmux python3; do
  command -v "$cmd" &>/dev/null || { echo "Error: $cmd not found" >&2; exit 1; }
done
[ -x "$CLAUDE_CLI" ] || { echo "Error: Claude CLI not executable: $CLAUDE_CLI" >&2; exit 1; }

# ── 日志 ──
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ── 清理 ──
cleanup() {
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux capture-pane -t "$SESSION_NAME" -p -S -3000 >> "$LOG_FILE" 2>/dev/null || true
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════
# Step 1: 创建 tmux 会话 + 打开可视化终端
# ══════════════════════════════════════════════════════════════
log "Creating tmux session: $SESSION_NAME"
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
tmux new-session -d -s "$SESSION_NAME" -x 200 -y 50

# 尝试用 iTerm 打开可视化窗口，失败则回退到 Terminal.app
if osascript -e 'tell application "iTerm" to activate' 2>/dev/null; then
  log "Opening iTerm window..."
  osascript <<ASCRIPT
tell application "iTerm"
  create window with default profile
  tell current session of current window
    write text "tmux attach-session -t $SESSION_NAME"
  end tell
end tell
ASCRIPT
else
  log "iTerm not found, falling back to Terminal.app..."
  osascript <<ASCRIPT
tell application "Terminal"
  activate
  do script "tmux attach-session -t $SESSION_NAME"
end tell
ASCRIPT
fi
sleep 2

# ══════════════════════════════════════════════════════════════
# Step 2: 在 tmux 中启动 Claude CLI 交互模式
# ══════════════════════════════════════════════════════════════
log "Starting Claude CLI (model: $CLAUDE_MODEL, skill: $SKILL_NAME)"
tmux send-keys -t "$SESSION_NAME" \
  "cd '$PROJECT_DIR' && '$CLAUDE_CLI' --model '$CLAUDE_MODEL' --dangerously-skip-permissions" \
  Enter

# 等待 Claude 初始化，验证其真正启动
log "Waiting for Claude to initialize..."
INIT_OK=false
for i in $(seq 1 12); do
  sleep 5
  PANE=$(tmux capture-pane -t "$SESSION_NAME" -p -S -10 2>/dev/null || echo "")

  # 检测信任提示并自动确认
  if echo "$PANE" | grep -qi "trust"; then
    tmux send-keys -t "$SESSION_NAME" Enter
    sleep 3
    continue
  fi

  # 检测 Claude 输入提示符（行首 ❯ 或 >，表示已就绪）
  if echo "$PANE" | grep -qE '^\s*(❯|>)'; then
    INIT_OK=true
    log "Claude is ready (waited ${i}x5s)"
    break
  fi

  # 检测启动失败
  if echo "$PANE" | grep -qiE 'Error:|error:'; then
    log "Error: Claude failed to start"
    tmux capture-pane -t "$SESSION_NAME" -p -S -20 >> "$LOG_FILE" 2>/dev/null
    exit 1
  fi
done

if [ "$INIT_OK" != true ]; then
  log "Error: Claude did not become ready within 60s"
  tmux capture-pane -t "$SESSION_NAME" -p -S -20 >> "$LOG_FILE" 2>/dev/null
  exit 1
fi

# ══════════════════════════════════════════════════════════════
# Step 3: 发送 skill 命令
# ══════════════════════════════════════════════════════════════
log "Sending skill command: /$SKILL_NAME"
tmux send-keys -t "$SESSION_NAME" "/$SKILL_NAME"
sleep 2
tmux send-keys -t "$SESSION_NAME" Enter
log "Skill command submitted, waiting ${WAIT_TIME}s for completion..."

# ══════════════════════════════════════════════════════════════
# Step 4: 等待1小时，然后退出 Claude 并记录结果
# ══════════════════════════════════════════════════════════════
sleep "$WAIT_TIME"

# 捕获输出
log "Capturing Claude output..."
tmux capture-pane -t "$SESSION_NAME" -p -S -3000 >> "$LOG_FILE" 2>/dev/null || true

# 发送 /exit 退出 Claude CLI
log "Sending /exit to Claude..."
tmux send-keys -t "$SESSION_NAME" "/exit" Enter
sleep 2

log "Session completed (skill: $SKILL_NAME, waited: ${WAIT_TIME}s)"
exit 0
