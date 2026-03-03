#!/usr/bin/env bash
# bobber-permission.sh — Sync permission handler for Bobber
# Connects to Bobber daemon via Unix socket, blocks until user decides.
set -euo pipefail

SOCKET_PATH="/tmp/bobber.sock"

if [ ! -S "$SOCKET_PATH" ]; then
    exit 0
fi

INPUT=$(cat)

detect_terminal() {
    if [ -n "${ITERM_SESSION_ID:-}" ]; then
        echo "iterm2" "${ITERM_SESSION_ID}"
        return
    fi
    local pid=$$
    for _ in 1 2 3 4 5; do
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$pid" ] || [ "$pid" = "1" ] && break
        local comm
        comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
        case "$comm" in
            *iTerm2*)    echo "iterm2" ""; return ;;
            *Terminal*)  echo "terminal" "$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')"; return ;;
            *ghostty*)   echo "ghostty" ""; return ;;
            *kitty*)     echo "kitty" ""; return ;;
            *Electron*)  echo "vscode" ""; return ;;
            *idea*|*webstorm*|*pycharm*) echo "jetbrains" ""; return ;;
        esac
    done
    if [ -n "${TMUX:-}" ]; then
        local ppid_tty
        ppid_tty=$(ps -p "$PPID" -o tty= 2>/dev/null | tr -d ' ')
        local tmux_target
        tmux_target=$(tmux list-panes -a -F '#{pane_tty} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null \
            | grep "$ppid_tty" | head -1 | awk '{print $2}')
        if [ -n "$tmux_target" ]; then
            echo "tmux" "$tmux_target"
            return
        fi
    fi
    echo "unknown" ""
}

read -r TERM_APP TERM_ID <<< "$(detect_terminal)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SESSION_ID="${CLAUDE_SESSION_ID:-$PPID-$(basename "${PWD}")}"

REQUEST_JSON=$(echo "$INPUT" | jq \
    --arg timestamp "$TIMESTAMP" \
    --arg pid "$PPID" \
    --arg sessionId "$SESSION_ID" \
    --arg projectPath "$PWD" \
    --arg projectName "$(basename "$PWD")" \
    --arg eventType "permission_prompt" \
    --arg termApp "$TERM_APP" \
    --arg termId "$TERM_ID" \
    '{
        version: 1,
        timestamp: $timestamp,
        pid: ($pid | tonumber),
        sessionId: $sessionId,
        projectPath: $projectPath,
        projectName: $projectName,
        eventType: $eventType,
        details: {
            tool: (.tool_name // .tool // "unknown"),
            command: ((.tool_input // {}) | .command // null),
            description: (.description // null)
        },
        terminal: { app: $termApp, tabId: $termId }
    }')

RESPONSE=$(echo "$REQUEST_JSON" | python3 -c "
import socket, json, sys

data = sys.stdin.read()
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.settimeout(300)
try:
    sock.connect('$SOCKET_PATH')
    sock.sendall(data.encode())
    response = sock.recv(4096).decode()
    print(response)
except (socket.timeout, ConnectionRefusedError, FileNotFoundError):
    sys.exit(0)
finally:
    sock.close()
" 2>/dev/null)

if [ -n "$RESPONSE" ]; then
    echo "$RESPONSE"
fi
