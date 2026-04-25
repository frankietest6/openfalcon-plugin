#!/bin/bash
# OpenFalcon plugin install script — runs once after FPP clones the repo

. ${FPPDIR}/scripts/common

# Make all command scripts and lifecycle scripts executable so FPP can run them.
# (git-tracked exec bit doesn't always survive every install path, so we do this
#  explicitly here to be safe.)
chmod +x /home/fpp/media/plugins/openfalcon/commands/*.php 2>/dev/null
chmod +x /home/fpp/media/plugins/openfalcon/scripts/*.sh 2>/dev/null

# Restart fppd after install so it picks up our commands and starts the listener
setSetting restartFlag 1
