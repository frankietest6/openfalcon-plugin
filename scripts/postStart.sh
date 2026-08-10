#!/bin/bash
# ShowPilot plugin postStart — runs every time fppd starts.
#
# Uses a lock file to guard against FPP running postStart twice on some
# versions, which caused the daemon to spawn twice and corrupt the relay
# with interleaved bytes from two instances.

PLUGIN_DIR="/home/fpp/media/plugins/showpilot"
LOG_DIR="/home/fpp/media/logs"
CONFIG_FILE="/home/fpp/media/config/plugin.showpilot"
LOCK_FILE="/tmp/showpilot-poststart.lock"
mkdir -p "$LOG_DIR"

# Poll for a PID to exit instead of a flat sleep — returns as soon as the
# process is actually gone, capped at $2 tenths-of-a-second.
wait_for_pid_exit() {
    local pid="$1" max_ticks="$2" ticks=0
    while kill -0 "$pid" 2>/dev/null && [ "$ticks" -lt "$max_ticks" ]; do
        sleep 0.1  # poll tick, not a flat wait — loop condition re-checks $pid every 0.1s and exits the instant it's gone
        ticks=$((ticks + 1))
    done
}

# Same idea for pkill'd processes we don't have a PID for — poll by pattern.
wait_for_pattern_exit() {
    local pattern="$1" max_ticks="$2" ticks=0
    while pgrep -f "$pattern" >/dev/null 2>&1 && [ "$ticks" -lt "$max_ticks" ]; do
        sleep 0.1  # poll tick, not a flat wait — loop condition re-checks the pattern every 0.1s and exits the instant it's gone
        ticks=$((ticks + 1))
    done
}

# Guard against double-invocation — FPP calls postStart twice on some versions.
# If another instance of this script is already running, exit immediately.
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE" 2>/dev/null)
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap "rm -f '$LOCK_FILE'" EXIT

# 1. Self-heal permissions
chmod +x "$PLUGIN_DIR/commands/"*.php 2>/dev/null
chmod +x "$PLUGIN_DIR/scripts/"*.sh 2>/dev/null
chmod +x "$PLUGIN_DIR/showpilot_listener.php" 2>/dev/null
chmod +x "$PLUGIN_DIR/listener_status.php" 2>/dev/null
chmod +x "$PLUGIN_DIR/extract_audio.php" 2>/dev/null
chmod +x "$PLUGIN_DIR/audio_daemon_status.php" 2>/dev/null

# Keep the plugin config writable. 660, not 666 — see fpp_install.sh for why
# group access (fpp:fpp) is sufficient here.
touch "$CONFIG_FILE" 2>/dev/null
chown fpp:fpp "$CONFIG_FILE" 2>/dev/null
chmod 660 "$CONFIG_FILE" 2>/dev/null

# 2. Kill any existing processes
# Try PID file first (clean), fall back to pkill (covers old installs)
if [ -f /tmp/showpilot-audio.pid ]; then
    OLD_PID=$(cat /tmp/showpilot-audio.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        wait_for_pid_exit "$OLD_PID" 5   # poll up to 0.5s instead of a flat sleep
        kill -9 "$OLD_PID" 2>/dev/null || true
    fi
    rm -f /tmp/showpilot-audio.pid
fi
pkill -f "php $PLUGIN_DIR/showpilot_listener.php" 2>/dev/null
pkill -f "node $PLUGIN_DIR/showpilot_audio.js" 2>/dev/null
wait_for_pattern_exit "php $PLUGIN_DIR/showpilot_listener.php" 10   # poll up to 1s instead of a flat sleep
wait_for_pattern_exit "node $PLUGIN_DIR/showpilot_audio.js" 10

# 3. Spawn listener
setsid /usr/bin/php "$PLUGIN_DIR/showpilot_listener.php" \
    </dev/null >/dev/null 2>&1 &

# ---- C++ MultiSync plugin is built during install/upgrade only ----
# fpp_install.sh already builds libshowpilot.so with `make`. Running that
# build synchronously here too, on every fppd startup, needlessly delays
# boot for no benefit (nothing changes between fppd restarts unless the
# plugin itself was reinstalled, which already rebuilds it). If it's
# missing, something went wrong at install time — log it and move on
# instead of blocking startup on a build.
if [ ! -f "$PLUGIN_DIR/libshowpilot.so" ] && [ -f "$PLUGIN_DIR/Makefile" ]; then
    echo "WARN: libshowpilot.so not found — MultiSync plugin was not built during install. Re-run the plugin's Install Script from FPP's Plugin Manager to rebuild it."
fi

# 4. Spawn audio daemon if Node 18+ available
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [ "${NODE_MAJOR:-0}" -ge 18 ]; then
        # Ensure ws module is installed — required for WebSocket position broadcast
        if [ ! -d "$PLUGIN_DIR/node_modules/ws" ]; then
            echo "Installing ws npm module..."
            cd "$PLUGIN_DIR" && npm install ws --save 2>/dev/null || true
        fi
        AUDIO_PORT=$(grep -E '^audioDaemonPort' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
        : "${AUDIO_PORT:=8090}"
        PORT="$AUDIO_PORT" \
        MEDIA_ROOT="/home/fpp/media/music" \
        FPP_HOST="http://127.0.0.1" \
        LOG_FILE="$LOG_DIR/plugin-showpilot-audio.log" \
        setsid /usr/bin/node --max-old-space-size=64 "$PLUGIN_DIR/showpilot_audio.js" \
            </dev/null >>"$LOG_DIR/plugin-showpilot-audio.log" 2>&1 &
    fi
fi

#postStart
