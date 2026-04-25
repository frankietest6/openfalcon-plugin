#!/bin/bash
# OpenFalcon plugin postStop — gracefully terminate both processes.

# Listener (PHP)
pkill -f "php /home/fpp/media/plugins/openfalcon/openfalcon_listener.php" 2>/dev/null

# Audio daemon (Node)
pkill -f "node openfalcon_audio.js" 2>/dev/null
pkill -f "node /home/fpp/media/plugins/openfalcon/openfalcon_audio.js" 2>/dev/null

#postStop
