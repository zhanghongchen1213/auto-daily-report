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

# Create logs directory
mkdir -p "$LOG_DIR"
echo "Created logs directory: $LOG_DIR"

# Make scripts executable
chmod +x "$SCRIPT_DIR/scripts/run-claude-tmux.sh"
chmod +x "$SCRIPT_DIR/scripts/gather-git-logs.sh"
echo "Made scripts executable"

# Ensure .claude/skills/ directory exists
mkdir -p "$SCRIPT_DIR/.claude/skills"
echo "Ensured .claude/skills/ directory exists"

# Ensure LaunchAgents directory exists
mkdir -p "$LAUNCH_AGENTS_DIR"

echo ""
echo "Installing launchd plists..."
for plist in "${PLISTS[@]}"; do
  SRC="$LAUNCHD_DIR/$plist"
  DST="$LAUNCH_AGENTS_DIR/$plist"

  if [ ! -f "$SRC" ]; then
    echo "  Warning: $SRC not found, skipping"
    continue
  fi

  # Unload existing if present
  if launchctl list | grep -q "${plist%.plist}" 2>/dev/null; then
    echo "  Unloading existing $plist..."
    launchctl unload "$DST" 2>/dev/null || true
  fi

  # Copy and load
  cp "$SRC" "$DST"
  launchctl load "$DST"
  echo "  Loaded: $plist"
done

echo ""
echo "Installation complete."
echo ""
echo "Schedule summary:"
echo "  Daily:   Mon-Sat at 22:00"
echo "  Weekly:  Sunday at 22:00"
echo "  Monthly: End of month at 22:00"
echo ""
echo "Logs directory: $LOG_DIR"
echo "To uninstall: bash $SCRIPT_DIR/uninstall.sh"
