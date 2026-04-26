#!/bin/bash
# ShowPilot plugin postStart — runs every time fppd starts.
#
# Kills any existing listener defensively before spawning a fresh one. This
# matters because:
#   1. If a user updated the plugin and clicked "Restart" in FPP UI, fppd
#      cycles. postStop should kill the old listener, but if anything went
#      wrong (postStop got skipped, kill signal lost, weird exit state), a
#      stale listener could survive into postStart. The pkill below catches it.
#   2. If postStart somehow gets called twice (shouldn't, but FPP edge cases
#      exist), the second call won't spawn a duplicate listener.
#
# After the kill+spawn, exactly one fresh listener exists, running the
# current code on disk.

PLUGIN_DIR="/home/fpp/media/plugins/showpilot"
LOG_DIR="/home/fpp/media/logs"
mkdir -p "$LOG_DIR"

# Kill any existing listener (idempotent — exit 0 if killed, 1 if none found,
# both fine here).
pkill -f "php $PLUGIN_DIR/showpilot_listener.php" 2>/dev/null

# Brief pause so SIGTERM takes effect cleanly before we spawn the replacement.
sleep 1

# Spawn the listener detached. setsid prevents fppd from holding onto it as a
# child process; redirecting stdio to /dev/null ensures the listener doesn't
# inherit the controlling terminal or wait on any descriptors.
setsid /usr/bin/php "$PLUGIN_DIR/showpilot_listener.php" \
    </dev/null >/dev/null 2>&1 &

#postStart
