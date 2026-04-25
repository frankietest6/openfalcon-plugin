#!/bin/bash
# OpenFalcon plugin postStart — launches the listener + audio daemon
# alongside fppd. Both are started detached so they survive script exit.

PLUGIN_DIR="/home/fpp/media/plugins/openfalcon"
LOG_DIR="/home/fpp/media/logs"
mkdir -p "$LOG_DIR"

# 1) PHP listener (handles voting, queue, plugin sync to OpenFalcon)
setsid /usr/bin/php "$PLUGIN_DIR/openfalcon_listener.php" \
    </dev/null >/dev/null 2>&1 &

# 2) Node.js audio daemon (Range-aware audio streaming + WS time sync).
#    Only starts if the user has enabled audio streaming in plugin config
#    AND Node + ws are installed.
ENABLE_AUDIO=$(grep -E '^audioStreamingEnabled' /home/fpp/media/config/plugin.openfalcon 2>/dev/null | cut -d'"' -f2)
if [ "$ENABLE_AUDIO" = "true" ]; then
    if command -v node >/dev/null 2>&1 && [ -f "$PLUGIN_DIR/openfalcon_audio.js" ]; then
        # Pull configurable port + media root from plugin config
        AUDIO_PORT=$(grep -E '^audioStreamingPort' /home/fpp/media/config/plugin.openfalcon 2>/dev/null | cut -d'"' -f2)
        : "${AUDIO_PORT:=8090}"

        cd "$PLUGIN_DIR"
        PORT="$AUDIO_PORT" \
        FPP_HOST="http://127.0.0.1" \
        MEDIA_ROOT="/home/fpp/media/music" \
        LOG_FILE="$LOG_DIR/openfalcon-audio.log" \
        setsid /usr/bin/node openfalcon_audio.js \
            </dev/null >>"$LOG_DIR/openfalcon-audio.log" 2>&1 &
    fi
fi

#postStart
