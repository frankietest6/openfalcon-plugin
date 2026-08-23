#!/bin/bash
# ============================================================
# ShowPilot Plugin — Deploy Script
# Run this from inside the plugin's own install directory on FPP
# (wherever FPP cloned it — see fpp_install.sh for why that name isn't
# assumed to be "showpilot" anymore).
# ============================================================
set -e

cd "$(dirname "$0")"
PLUGIN_DIR="$(pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}→ Pulling latest from git...${NC}"
git pull

echo -e "${YELLOW}→ Fixing permissions...${NC}"
sudo chmod +x scripts/*.sh commands/*.php 2>/dev/null || true
sudo chown -R fpp:fpp .

echo -e "${YELLOW}→ Restarting listener...${NC}"
sudo pkill -f showpilot_listener || true
sleep 1
nohup php "$PLUGIN_DIR/showpilot_listener.php" > /dev/null 2>&1 &
disown

echo
echo -e "${GREEN}✓ Deploy complete. Tail the log to verify:${NC}"
echo "  tail -f /home/fpp/media/logs/plugin-showpilot.log"
