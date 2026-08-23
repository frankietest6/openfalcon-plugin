#!/bin/bash
# ShowPilot plugin postStop — gracefully terminate the listener when fppd
# stops. fppd would eventually clean up its child processes anyway, but doing
# it explicitly here ensures a clean shutdown sequence and gives the listener
# a chance to send any final state to the server before exiting.

# Derived, not hardcoded (fpp-data#209 fallout — see fpp_install.sh's
# comment for the full story). FPP invokes postStop.sh by its own full path.
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkill -f "php $PLUGIN_DIR/showpilot_listener.php" 2>/dev/null
pkill -f "node $PLUGIN_DIR/showpilot_audio.js" 2>/dev/null

#postStop
