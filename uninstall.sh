#!/bin/bash
# uninstall.sh - Remove auto-report launchd schedules
set -euo pipefail

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

PLISTS=(
  "com.auto-report.daily.plist"
  "com.auto-report.weekly.plist"
  "com.auto-report.monthly.plist"
)

echo "=== Auto Report Uninstaller ==="
echo ""

for plist in "${PLISTS[@]}"; do
  DST="$LAUNCH_AGENTS_DIR/$plist"

  if [ -f "$DST" ]; then
    echo "Unloading $plist..."
    launchctl unload "$DST" 2>/dev/null || true
    rm -f "$DST"
    echo "  Removed: $plist"
  else
    echo "  Not installed: $plist"
  fi
done

echo ""
echo "All scheduled tasks removed."
echo "Project files remain in place. Delete the project directory manually if needed."
