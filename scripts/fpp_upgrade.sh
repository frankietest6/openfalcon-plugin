#!/bin/bash
# ShowPilot plugin upgrade script.
#
# FPP's own scripts/upgrade_plugin wrapper looks for this file FIRST when
# the user clicks "Update" in the Plugin Manager (or ShipPilot triggers the
# same flow) — it already did `git fetch`/`git reset --hard` on our repo
# before calling us, then runs this in preference to fpp_install.sh. If
# this file didn't exist, it would fall back to fpp_install.sh instead,
# which is built for a fresh install and unconditionally requests a full
# fppd restart — correct there, but overkill for a routine version bump.
#
# What "Update" actually does to fppd, confirmed by reading FPP's own
# www/api/controllers/plugin.php (UpgradePlugin()) and src/Plugins.cpp on
# FalconChristmas/fpp master: the Update flow does NOT call fppd's plugin
# load/unload lifecycle the way a fresh Install or a full Uninstall does.
# It only re-runs this script. So without doing the work ourselves here,
# fppd would keep running the OLD copy of libshowpilot.so in memory after
# every update, invisibly, regardless of FPP version — restartFlag was
# actually covering for that, not just pre-FPP10 hosts.
#
# FPP 10+ genuinely can hot-swap a plugin's compiled .so at runtime
# (PluginManager::loadPlugin()/unloadPlugin(), reachable at
# http://localhost/api/fppd/plugin/<name>/<load|unload>) — our C++ class
# already cleans up correctly for this (its destructor calls
# MultiSync::INSTANCE.removeMultiSyncPlugin()), and our own `make clean &&
# make` naturally gives the rebuilt .so a fresh inode, which is exactly
# what FPP's loader needs to see to treat it as new code rather than
# handing back the still-mapped old copy. That endpoint doesn't exist on
# FPP 9 and older, so every step below is written to degrade safely: if
# fppd doesn't confirm the hot-unload/hot-load, or anything else here
# fails, we fall back to setSetting restartFlag 1 exactly like
# fpp_install.sh always has.
#
# The PHP listener and Node audio daemon are untouched by any of the
# fppd plugin-lifecycle machinery above — they're plain background
# processes started by postStart.sh, not something PluginManager dlopen's
# — so they always get restarted here directly, independent of whether
# the C++ hot-reload above succeeded.
#
# Deliberately no `set -e` here (unlike fpp_install.sh): every step is
# optional-with-a-fallback by design, so a failure partway through should
# fall through to the restart-required path at the end, not abort mid-way
# and leave some pieces restarted and others not.

. ${FPPDIR}/scripts/common

PLUGIN_DIR="/home/fpp/media/plugins/showpilot"
PLUGIN_NAME="showpilot"
HOTRELOAD_OK=1

# ---- 1. Ask fppd to unload the currently-running C++ plugin (if any).
# Only implemented on FPP 10+; a failed/empty response here is the expected
# result on older FPP and just means we fall back to restartFlag below.
unload_resp=$(curl -s -m 5 -X POST "http://localhost/api/fppd/plugin/${PLUGIN_NAME}/unload" 2>/dev/null)
if echo "$unload_resp" | grep -q '"Status"[[:space:]]*:[[:space:]]*"OK"'; then
    echo "fppd confirmed plugin unload"
else
    echo "WARN: fppd hot-unload not confirmed (older FPP, or fppd not reachable) — will request a restart instead"
    HOTRELOAD_OK=0
fi

# ---- 2. Rebuild the C++ MultiSync plugin against the freshly-pulled
# source. `make clean` removes the old .so first, so the rebuilt file gets
# a new inode — see the header comment above for why that matters.
rm -f "$PLUGIN_DIR/libshowpilot.so" 2>/dev/null || true
if [ -f "$PLUGIN_DIR/Makefile" ] && [ -d "/opt/fpp/src" ]; then
    echo "Rebuilding ShowPilot MultiSync plugin..."
    if (cd "$PLUGIN_DIR" && make clean && make) 2>&1; then
        echo "ShowPilot MultiSync plugin rebuilt successfully"
    else
        echo "WARN: C++ plugin rebuild failed — falling back to HTTP polling until a restart"
        HOTRELOAD_OK=0
    fi
else
    echo "WARN: FPP source not found at /opt/fpp/src — skipping C++ plugin rebuild"
    HOTRELOAD_OK=0
fi

# ---- 3. Ask fppd to load the rebuilt plugin back in. Only bother if step
# 1 actually confirmed fppd supports this — otherwise we already know we
# need a restart, and calling load() against a plugin fppd never unloaded
# would just no-op ("already running; nothing to do") on the stale copy.
if [ "$HOTRELOAD_OK" = "1" ]; then
    load_resp=$(curl -s -m 5 -X POST "http://localhost/api/fppd/plugin/${PLUGIN_NAME}/load" 2>/dev/null)
    if echo "$load_resp" | grep -q '"Status"[[:space:]]*:[[:space:]]*"OK"'; then
        echo "fppd confirmed plugin load — new MultiSync code is live, no restart needed for it"
    else
        echo "WARN: fppd hot-load not confirmed — will request a restart instead"
        HOTRELOAD_OK=0
    fi
fi

# ---- 4. Restart the Node audio daemon and PHP listener in place. These
# always run, regardless of steps 1-3, since nothing above touches them.
chmod +x "$PLUGIN_DIR/scripts/"*.sh "$PLUGIN_DIR/commands/"*.php 2>/dev/null || true

if [ -x "$PLUGIN_DIR/scripts/restart-daemon.sh" ]; then
    "$PLUGIN_DIR/scripts/restart-daemon.sh" || { echo "WARN: audio daemon restart reported a problem"; HOTRELOAD_OK=0; }
fi

if command -v php >/dev/null 2>&1 && [ -f "$PLUGIN_DIR/commands/restart_listener.php" ]; then
    php "$PLUGIN_DIR/commands/restart_listener.php" >/dev/null 2>&1 || { echo "WARN: listener restart reported a problem"; HOTRELOAD_OK=0; }
fi

# ---- 5. Only ask FPP to restart fppd if something above didn't confirm.
if [ "$HOTRELOAD_OK" = "1" ]; then
    echo "ShowPilot updated in place — no fppd restart needed"
else
    setSetting restartFlag 1
fi

#fpp_upgrade
