#!/bin/bash
# uninstall.sh - 卸载自动报告 launchd 定时任务
set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

PLISTS=(
  "com.auto-report.daily.plist"
  "com.auto-report.weekly.plist"
  "com.auto-report.monthly.plist"
)

echo "=== 自动报告卸载程序 ==="
echo ""

for plist in "${PLISTS[@]}"; do
  DST="$LAUNCH_AGENTS_DIR/$plist"

  if [ -f "$DST" ]; then
    echo "正在卸载 $plist..."
    launchctl unload "$DST" 2>/dev/null || true
    rm -f "$DST"
    echo "  已移除: $plist"
  else
    echo "  未安装: $plist"
  fi
done

echo ""
echo "所有定时任务已移除。"
echo "项目文件和日志保留在原位。"
echo "如需删除项目目录，请手动操作。"
