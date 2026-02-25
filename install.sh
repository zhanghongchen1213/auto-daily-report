#!/bin/bash
# install.sh - Install auto-report launchd schedules on macOS
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

echo "=== Auto Report Installer ==="
echo ""

# Ensure logs directory exists
mkdir -p "$LOG_DIR"

# Ensure scripts are executable
chmod +x "$SCRIPT_DIR/scripts/"*.sh

# Ensure LaunchAgents directory exists
mkdir -p "$LAUNCH_AGENTS_DIR"

for plist in "${PLISTS[@]}"; do
  SRC="$LAUNCHD_DIR/$plist"
  DST="$LAUNCH_AGENTS_DIR/$plist"

  if [ ! -f "$SRC" ]; then
    echo "Warning: $SRC not found, skipping"
    continue
  fi

  # Unload existing if present
  if launchctl list | grep -q "${plist%.plist}" 2>/dev/null; then
    echo "Unloading existing $plist..."
    launchctl unload "$DST" 2>/dev/null || true
  fi

  # Copy and load
  echo "Installing $plist..."
  cp "$SRC" "$DST"
  launchctl load "$DST"
  echo "  Loaded: $plist"
done

echo ""
echo "Installation complete. Scheduled tasks:"
echo "  - Daily report:   Mon-Sat at 22:00"
echo "  - Weekly report:  Saturday at 16:30"
echo "  - Monthly report: Last working day at 17:00"
echo ""
echo "Logs directory: $LOG_DIR"
echo "To uninstall: bash $SCRIPT_DIR/uninstall.sh"
