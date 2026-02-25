#!/bin/bash
# install.sh - 安装自动报告 launchd 定时任务（macOS）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHD_DIR="$SCRIPT_DIR/launchd"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$SCRIPT_DIR/logs"

PLISTS=(
  "com.auto-report.daily.plist"
  "com.auto-report.weekly.plist"
  "com.auto-report.monthly.plist"
)

echo "=== 自动报告安装程序 ==="
echo ""

# 创建日志目录
mkdir -p "$LOG_DIR"
echo "已创建日志目录: $LOG_DIR"

# 赋予脚本执行权限
chmod +x "$SCRIPT_DIR/scripts/run-claude-tmux.sh"
chmod +x "$SCRIPT_DIR/scripts/gather-git-logs.sh"
echo "已赋予脚本执行权限"

# 确保 .claude/skills/ 目录存在
mkdir -p "$SCRIPT_DIR/.claude/skills"
echo "已确认 .claude/skills/ 目录存在"

# 确保 LaunchAgents 目录存在
mkdir -p "$LAUNCH_AGENTS_DIR"

echo ""
echo "正在安装 launchd 定时任务..."
for plist in "${PLISTS[@]}"; do
  SRC="$LAUNCHD_DIR/$plist"
  DST="$LAUNCH_AGENTS_DIR/$plist"

  if [ ! -f "$SRC" ]; then
    echo "  警告: $SRC 不存在，跳过"
    continue
  fi

  # 卸载已有的任务
  if launchctl list | grep -q "${plist%.plist}" 2>/dev/null; then
    echo "  正在卸载已有的 $plist..."
    launchctl unload "$DST" 2>/dev/null || true
  fi

  # 复制并加载
  cp "$SRC" "$DST"
  launchctl load "$DST"
  echo "  已加载: $plist"
done

echo ""
echo "安装完成。"
echo ""
echo "定时任务概览:"
echo "  日报:   周一至周六 22:00"
echo "  周报:   周日 22:00"
echo "  月报:   每月最后一天 22:00"
echo ""
echo "日志目录: $LOG_DIR"
echo "卸载命令: bash $SCRIPT_DIR/uninstall.sh"
