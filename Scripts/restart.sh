#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BINARY="$PROJECT_DIR/.build/Bobber.app/Contents/MacOS/Bobber"
DEBUG_BINARY="$PROJECT_DIR/.build/arm64-apple-macosx/debug/Bobber"
LOG_FILE="/tmp/bobber-stdout.log"

# Kill existing
pkill -f "MacOS/Bobber" 2>/dev/null && echo "Stopped old Bobber" || true
sleep 1

# Build
echo "Building..."
cd "$PROJECT_DIR"
swift build 2>&1 | tail -3

# Copy binary to app bundle
cp "$DEBUG_BINARY" "$APP_BINARY"

# Launch
nohup "$APP_BINARY" > "$LOG_FILE" 2>&1 &
sleep 1
PID=$(pgrep -f "MacOS/Bobber" || true)
if [ -n "$PID" ]; then
    echo "Bobber running (PID $PID)"
else
    echo "Failed to start Bobber"
    exit 1
fi
