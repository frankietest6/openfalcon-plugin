#!/bin/bash
# ShowPilot plugin postStop — gracefully terminate the listener.

# Listener (PHP)
pkill -f "php /home/fpp/media/plugins/showpilot/showpilot_listener.php" 2>/dev/null

#postStop
