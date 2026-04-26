#!/bin/bash
# ShowPilot plugin postStart — launches the PHP listener alongside fppd.
# Started detached so it survives script exit.

PLUGIN_DIR="/home/fpp/media/plugins/showpilot"
LOG_DIR="/home/fpp/media/logs"
mkdir -p "$LOG_DIR"

# PHP listener (handles voting, queue, plugin sync to ShowPilot)
setsid /usr/bin/php "$PLUGIN_DIR/showpilot_listener.php" \
    </dev/null >/dev/null 2>&1 &

#postStart
