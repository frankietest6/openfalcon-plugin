# OpenFalcon FPP Plugin

The Falcon Player (FPP) plugin for [OpenFalcon](https://github.com/frankietest6/openfalcon) — a self-hosted replacement for Remote Falcon.

This plugin connects an FPP instance to your OpenFalcon server. It reports playback state to OpenFalcon and queues sequences when viewers vote or make jukebox requests.

## What this plugin does

- Polls FPP's status API (`/api/system/status`) every second by default
- Reports the currently playing sequence and what's coming up next to OpenFalcon
- Asks OpenFalcon what to play next (vote winner or jukebox request)
- Queues that sequence in FPP via `Insert Playlist Immediate` or `Insert Playlist After Current`
- Pushes the playlist contents to OpenFalcon so the viewer page knows what songs exist
- Heartbeats back to OpenFalcon so the admin page can show plugin connectivity

## Requirements

- FPP 5.0 or newer (tested on FPP 9.5)
- A running [OpenFalcon](https://github.com/frankietest6/openfalcon) server reachable from the FPP

## Install

### Via FPP Plugin Manager (recommended once it's in the master plugin list)

**Pending** — once this plugin is added to the [FalconChristmas plugin list](https://github.com/FalconChristmas/fpp-pluginList) you'll be able to install with one click. For now, install manually.

### Manual install

```bash
# On the FPP, in a terminal:
cd /home/fpp/media/plugins
git clone https://github.com/frankietest6/openfalcon-plugin.git openfalcon
sudo chmod +x openfalcon/scripts/*.sh openfalcon/commands/*.php
sudo chown -R fpp:fpp openfalcon
sudo reboot
```

After reboot, the plugin should appear in **Content Setup → Plugin Manager**. Open the plugin's config page and fill in:

- **Server URL**: `http://your-openfalcon-server:3100` (no trailing slash)
- **Show Token**: copy from your OpenFalcon admin page → "Show Token (for OpenFalcon Plugin)" section
- **Remote Playlist**: select the FPP playlist that contains your viewer-controllable sequences

Then click **Sync Playlist to OpenFalcon**. Sequences should appear in the OpenFalcon admin.

## Updating

```bash
cd /home/fpp/media/plugins/openfalcon
git pull
sudo chmod +x scripts/*.sh commands/*.php
sudo chown -R fpp:fpp .
# Restart the listener via FPP's Command Scheduler or:
sudo pkill -f openfalcon_listener
nohup php /home/fpp/media/plugins/openfalcon/openfalcon_listener.php > /dev/null 2>&1 &
disown
```

## FPP Commands

The plugin exposes several commands you can schedule via FPP's command preset/scheduler:

| Command | Effect |
|---|---|
| OpenFalcon - Turn Viewer Control On | Restores last active mode (Voting or Jukebox) |
| OpenFalcon - Turn Viewer Control Off | Disables viewer control |
| OpenFalcon - Switch to Voting Mode | Forces voting mode |
| OpenFalcon - Switch to Jukebox Mode | Forces jukebox mode |
| OpenFalcon - Restart Listener | Reloads plugin config |
| OpenFalcon - Stop Listener | Stops the listener (turns plugin off) |
| OpenFalcon - Turn Interrupt Schedule On | Force-on the "interrupt schedule" plugin setting |
| OpenFalcon - Turn Interrupt Schedule Off | Force-off the same |

A typical setup: schedule "Turn Viewer Control On" 30 minutes before showtime, "Turn Viewer Control Off" at end-of-night.

## Architecture

```
[FPP]  ──┬─▶ /api/system/status  (polled by listener)
         └─▶ /api/command/Insert Playlist Immediate (queues viewer picks)
              ▲
              │
[Plugin Listener (PHP)] ──HTTP──▶  [OpenFalcon Server]
   |
   └── Reads /home/fpp/media/playlists/<remote-playlist>.json
       to determine "next up" and to sync sequence list
```

The listener is a long-running PHP process (started by FPP's plugin system at boot via `scripts/postStart.sh`). It polls every second and is gentle on FPP's CPU.

## Troubleshooting

**Plugin UI page won't save settings**
FPP 9+ moved its plugin JS helpers. The plugin uses FPP's REST API directly to save settings. If your FPP is older than 5.0 this won't work — upgrade FPP.

**CSP errors in browser console when clicking Sync**
FPP's Apache has a strict Content-Security-Policy that blocks connections to non-whitelisted domains. Add your OpenFalcon URL:

```bash
sudo /opt/fpp/scripts/ManageApacheContentPolicy.sh add connect-src http://192.168.1.230:3100
sudo systemctl restart apache2
```

**Listener log location**
`/home/fpp/media/logs/openfalcon-listener.log`

```bash
tail -f /home/fpp/media/logs/openfalcon-listener.log
```

**Plugin queues wrong song**
Make sure you've clicked **Sync Playlist** in the plugin UI after any changes to your FPP playlist contents/order.

## License

MIT — see [LICENSE](./LICENSE).
