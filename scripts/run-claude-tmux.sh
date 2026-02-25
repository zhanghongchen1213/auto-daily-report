#!/bin/bash
# run-claude-tmux.sh - 打开可视化终端，启动 Claude CLI 交互模式，发送 prompt
# 用法: run-claude-tmux.sh <prompt_file> <log_file> [model] [max_turns]
#
# 流程：tmux 会话 → iTerm 可视化窗口 → claude 交互模式 → bracketed paste 发送 prompt
# Claude 交互模式自动加载 ~/.claude/.mcp.json，无需显式配置 MCP。

set -euo pipefail

# ── 参数解析 ──
PROMPT_FILE="${1:?Usage: run-claude-tmux.sh <prompt_file> <log_file> [model] [max_turns]}"
LOG_FILE="${2:?Usage: run-claude-tmux.sh <prompt_file> <log_file> [model] [max_turns]}"
CLAUDE_MODEL="${3:-sonnet}"
MAX_TURNS="${4:-25}"

# ── 配置 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_DIR/config.json"

CLAUDE_CLI=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
print(config.get('claude', {}).get('cli_path', 'claude'))
")

SESSION_NAME="claude-report-$(date +%s)"
MAX_WAIT=600
POLL_INTERVAL=10

# ── 前置检查 ──
for cmd in tmux python3; do
  command -v "$cmd" &>/dev/null || { echo "Error: $cmd not found" >&2; exit 1; }
done
[ -f "$PROMPT_FILE" ] || { echo "Error: Prompt not found: $PROMPT_FILE" >&2; exit 1; }
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
log "Starting Claude CLI (model: $CLAUDE_MODEL, max-turns: $MAX_TURNS)"
tmux send-keys -t "$SESSION_NAME" \
  "cd '$PROJECT_DIR' && '$CLAUDE_CLI' --model '$CLAUDE_MODEL' --max-turns $MAX_TURNS" \
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

  # 检测 Claude 输入提示符（表示已就绪）
  if echo "$PANE" | grep -qE '>\s*$'; then
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
# Step 3: 通过 bracketed paste 发送长 prompt
# -p 标志启用 bracketed paste mode，换行不会触发提交
# ══════════════════════════════════════════════════════════════
log "Sending prompt via bracketed paste: $PROMPT_FILE"
tmux load-buffer -b prompt-buf "$PROMPT_FILE"
tmux paste-buffer -t "$SESSION_NAME" -b prompt-buf -d -p
sleep 1

# 发送 Enter 提交 prompt
tmux send-keys -t "$SESSION_NAME" Enter
log "Prompt submitted, waiting for Claude to process..."

# ══════════════════════════════════════════════════════════════
# Step 4: 轮询检测 Claude 是否完成
# 交互模式完成标志：输入提示符重新出现（> 或 ❯）
# ══════════════════════════════════════════════════════════════
ELAPSED=0
COMPLETED=false

# 先等 30 秒，给 Claude 处理时间
sleep 30
ELAPSED=30

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  PANE_TAIL=$(tmux capture-pane -t "$SESSION_NAME" -p -S -5 2>/dev/null || echo "")

  # 检测 Claude 回到空闲输入状态
  if echo "$PANE_TAIL" | grep -qE '>\s*$'; then
    sleep 5
    RECHECK=$(tmux capture-pane -t "$SESSION_NAME" -p -S -3 2>/dev/null || echo "")
    if echo "$RECHECK" | grep -qE '>\s*$'; then
      COMPLETED=true
      break
    fi
  fi

  log "Still processing... (${ELAPSED}s / ${MAX_WAIT}s)"
done

# ══════════════════════════════════════════════════════════════
# Step 5: 捕获输出，退出 Claude，记录结果
# ══════════════════════════════════════════════════════════════
log "Capturing Claude output..."
tmux capture-pane -t "$SESSION_NAME" -p -S -3000 >> "$LOG_FILE" 2>/dev/null || true

if [ "$COMPLETED" = true ]; then
  log "Claude completed successfully (${ELAPSED}s elapsed)"
  # 发送 /exit 退出 Claude CLI
  tmux send-keys -t "$SESSION_NAME" "/exit" Enter
  sleep 2
  exit 0
else
  log "Error: Claude did not complete within ${MAX_WAIT}s timeout"
  # 超时也尝试退出
  tmux send-keys -t "$SESSION_NAME" "/exit" Enter
  sleep 2
  exit 1
fi
