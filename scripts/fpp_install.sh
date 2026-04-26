#!/bin/bash
# ShowPilot plugin install script
#
# Runs after FPP clones the repo, AND any time the user clicks
# "Run Install Script" or updates the plugin via FPP's plugin manager.
#
# We force-sync with origin/main here because FPP's built-in updater
# is unreliable about actually pulling fresh code. Doing it ourselves
# guarantees an Update click is always honored.

. ${FPPDIR}/scripts/common

PLUGIN_DIR="/home/fpp/media/plugins/showpilot"

# Force-sync with origin/main, discarding any local changes.
# (Plugin code lives entirely in the repo — there shouldn't be any
#  local edits worth preserving. User config lives in
#  /home/fpp/media/config/plugin.showpilot, separate.)
if [ -d "$PLUGIN_DIR/.git" ]; then
    cd "$PLUGIN_DIR"
    git fetch origin 2>&1 || echo "WARN: git fetch failed (no internet?)"
    git reset --hard origin/main 2>&1 || echo "WARN: git reset failed"
fi

# Ensure correct ownership
chown -R fpp:fpp "$PLUGIN_DIR" 2>/dev/null

# Make all command scripts and lifecycle scripts executable so FPP can run them.
# (git-tracked exec bit doesn't always survive every install path, so we do this
#  explicitly here to be safe.)
chmod +x "$PLUGIN_DIR/commands/"*.php 2>/dev/null
chmod +x "$PLUGIN_DIR/scripts/"*.sh 2>/dev/null

# Restart the listener directly so it picks up the new code immediately, without
# requiring an fppd restart. PHP doesn't hot-reload — a running listener
# process holds its loaded code in memory regardless of file changes on disk,
# so we MUST kill the old process and spawn a fresh one for plugin updates to
# take effect.
#
# We use the same restart command exposed in the FPP UI ("ShowPilot - Restart
# Listener"). It does kill-then-spawn defensively, so it's safe to call whether
# or not a listener is currently running.
if [ -f "$PLUGIN_DIR/commands/restart_listener.php" ]; then
    /usr/bin/php "$PLUGIN_DIR/commands/restart_listener.php" 2>&1 || true
fi

# Set restartFlag for any FPP version where the plugin manager UI checks it
# to surface the "restart required" banner. The listener restart above already
# took effect; this just keeps the UI honest.
setSetting restartFlag 1
