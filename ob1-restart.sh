#!/bin/bash
TELEGRAM_BOT_TOKEN=$(grep TELEGRAM_BOT_TOKEN /volume1/docker/OB1/.env 2>/dev/null | cut -d= -f2)
TELEGRAM_CHAT_ID="725925511"
SESSION_NAME="OB1"
WORK_DIR="/volume1/docker/OB1"
LOG_FILE="/volume1/docker/OB1/watchdog.log"

send_telegram() {
    local msg="$1"
    [ -z "$TELEGRAM_BOT_TOKEN" ] && return
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${msg}" \
        -d parse_mode="Markdown" > /dev/null 2>&1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "OB1 watchdog starting"
source /home/john/.bash_profile 2>/dev/null || true
export PATH="/home/john/.bun/bin:$PATH"
export HOME="/home/john"

# Guard: if a healthy OB1 session already exists, attach to it and wait — don't spawn a duplicate
if tmux -S /tmp/ob1.sock has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "Session '$SESSION_NAME' already exists — attaching to existing session (no duplicate spawned)"
    PANE_PID=$(tmux -S /tmp/ob1.sock list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
    if [ -n "$PANE_PID" ] && kill -0 "$PANE_PID" 2>/dev/null; then
        log "Existing session is healthy (pane PID $PANE_PID) — waiting for it to exit"
        wait "$PANE_PID" 2>/dev/null || true
        log "OB1 tmux session ended — systemd will restart"
        exit 0
    else
        log "Existing session has dead pane — killing and recreating"
        tmux -S /tmp/ob1.sock kill-session -t "$SESSION_NAME" 2>/dev/null || true
        sleep 2
    fi
fi

# Use script to allocate a PTY so claude doesn't add --print
tmux -S /tmp/ob1.sock new-session -d -s "$SESSION_NAME" -c "$WORK_DIR" \
    "script -q -c 'claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official' /dev/null 2>&1 | tee -a $LOG_FILE"
chmod 666 /tmp/ob1.sock 2>/dev/null || true

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    log "OB1 tmux session started successfully"
    send_telegram "🔄 *OB1 Life Engine restarted* — tmux session started on dnas."
else
    log "ERROR: Failed to start OB1 tmux session (exit code $EXIT_CODE)"
    send_telegram "❌ *OB1 watchdog FAILED* — manual intervention required."
    exit 1
fi

PANE_PID=$(tmux -S /tmp/ob1.sock list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
wait "$PANE_PID" 2>/dev/null || true
log "OB1 tmux session ended — systemd will restart"
