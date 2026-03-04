#!/usr/bin/env bash
# bobber-event.sh — Async event capture for Bobber
# Receives JSON from Claude Code on stdin, writes to ~/.bobber/events/
set -euo pipefail

EVENT_TYPE="${1:-unknown}"
EVENTS_DIR="${HOME}/.bobber/events"
SOCKET_PATH="/tmp/bobber.sock"

mkdir -p "$EVENTS_DIR"

# Read hook data from stdin
INPUT=$(cat)

# Detect terminal
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

# Extract tool summary
tool_summary() {
    local tool_name
    tool_name=$(echo "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)
    local tool_input
    tool_input=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)
    case "$tool_name" in
        Bash)    echo "$ $(echo "$tool_input" | jq -r '.command // ""' 2>/dev/null | head -c 60)" ;;
        Edit)    echo "$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)" ;;
        Write)   echo "$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)" ;;
        Read)    echo "$(echo "$tool_input" | jq -r '.file_path // ""' 2>/dev/null)" ;;
        Grep)    echo "grep: $(echo "$tool_input" | jq -r '.pattern // ""' 2>/dev/null | head -c 40)" ;;
        Glob)    echo "glob: $(echo "$tool_input" | jq -r '.pattern // ""' 2>/dev/null | head -c 40)" ;;
        *)       echo "$tool_name" ;;
    esac
}

read -r TERM_APP TERM_ID <<< "$(detect_terminal)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Extract session ID from hook JSON (prefer real session_id over fallback)
HOOK_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID="${HOOK_SESSION_ID:-${CLAUDE_SESSION_ID:-$PPID-$(basename "${PWD}")}}"

# Extract session title from transcript (first user message, cached per session)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_TITLE=""
TITLE_CACHE="${HOME}/.bobber/.title-cache"
mkdir -p "$TITLE_CACHE"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    CACHE_FILE="${TITLE_CACHE}/${SESSION_ID}"
    if [ -f "$CACHE_FILE" ]; then
        SESSION_TITLE=$(cat "$CACHE_FILE")
    else
        SESSION_TITLE=$(python3 -c "
import json, sys
with open('$TRANSCRIPT_PATH') as f:
    for line in f:
        try:
            d = json.loads(line)
            if d.get('type') == 'user':
                msg = d.get('message',{}).get('content','')
                texts = []
                if isinstance(msg, list):
                    texts = [p['text'] for p in msg if isinstance(p, dict) and p.get('type') == 'text']
                elif isinstance(msg, str):
                    texts = [msg]
                for t in texts:
                    for l in t.split('\n'):
                        l = l.strip()
                        if l and not l.startswith('<') and not l.startswith('Base directory'):
                            print(l[:60]); sys.exit(0)
        except Exception: pass
" 2>/dev/null || true)
        [ -n "$SESSION_TITLE" ] && echo "$SESSION_TITLE" > "$CACHE_FILE"
    fi
fi

PROJECT_PATH="${CLAUDE_PROJECT_DIR:-${PWD}}"
PROJECT_NAME="$(basename "${PROJECT_PATH}")"

case "$EVENT_TYPE" in
    SessionStart)      BOBBER_TYPE="session_start" ;;
    PreToolUse)        BOBBER_TYPE="pre_tool_use" ;;
    Notification)      BOBBER_TYPE="notification" ;;
    Stop)              BOBBER_TYPE="stop" ;;
    TaskCompleted)     BOBBER_TYPE="task_completed" ;;
    UserPromptSubmit)  BOBBER_TYPE="user_prompt_submit" ;;
    SessionEnd)        BOBBER_TYPE="session_end" ;;
    *)                 BOBBER_TYPE="$EVENT_TYPE" ;;
esac

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .tool // empty' 2>/dev/null)
SUMMARY=$(tool_summary)

EVENT_JSON=$(jq -n \
    --arg version "1" \
    --arg timestamp "$TIMESTAMP" \
    --arg pid "$PPID" \
    --arg sessionId "$SESSION_ID" \
    --arg projectPath "$PROJECT_PATH" \
    --arg projectName "$PROJECT_NAME" \
    --arg sessionTitle "$SESSION_TITLE" \
    --arg eventType "$BOBBER_TYPE" \
    --arg tool "$TOOL_NAME" \
    --arg summary "$SUMMARY" \
    --arg termApp "$TERM_APP" \
    --arg termId "$TERM_ID" \
    '{
        version: ($version | tonumber),
        timestamp: $timestamp,
        pid: ($pid | tonumber),
        sessionId: $sessionId,
        projectPath: $projectPath,
        projectName: $projectName,
        sessionTitle: (if $sessionTitle == "" then null else $sessionTitle end),
        eventType: $eventType,
        details: { tool: $tool, description: $summary },
        terminal: { app: $termApp, tabId: $termId }
    }')

TEMP=$(mktemp "${EVENTS_DIR}/.tmp.XXXXXX")
trap 'rm -f "$TEMP"' EXIT
echo "$EVENT_JSON" > "$TEMP"
mv "$TEMP" "${EVENTS_DIR}/${TIMESTAMP//[:-]/}-$$.json"

if [ -S "$SOCKET_PATH" ]; then
    echo "ping" | nc -U "$SOCKET_PATH" -w 1 2>/dev/null || true
fi
