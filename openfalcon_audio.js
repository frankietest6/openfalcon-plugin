#!/usr/bin/env node
/**
 * OpenFalcon Audio Daemon
 *
 * Runs alongside the existing PHP listener on FPP. Provides:
 *   GET  /audio/<file>     — Range-aware MP3 streaming from FPP's media folder
 *   GET  /now              — current sequence + position (REST polling fallback)
 *   WS   /sync             — broadcasts {sequence, position} 4× per second
 *   GET  /health           — liveness check
 *
 * Polls FPP's /api/fppd/status to track playback position. Uses ws library
 * for WebSocket support (auto-installed by fpp_install.sh on first run).
 *
 * Configuration (via CLI or env):
 *   PORT                        listen port, default 8090
 *   FPP_HOST                    FPP's own API, default http://localhost
 *   MEDIA_ROOT                  audio files dir, default /home/fpp/media/music
 *   POLL_INTERVAL_MS            FPP status poll, default 250
 *   LOG_FILE                    log file, default /home/fpp/media/logs/openfalcon-audio.log
 *
 * Hands off cleanly on SIGTERM. Kept minimal — no deps beyond `ws`.
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const url = require('url');

// ---------- Config ----------
const PORT = parseInt(process.env.PORT || '8090', 10);
const FPP_HOST = process.env.FPP_HOST || 'http://127.0.0.1';
const MEDIA_ROOT = process.env.MEDIA_ROOT || '/home/fpp/media/music';
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '250', 10);
const LOG_FILE = process.env.LOG_FILE || '/home/fpp/media/logs/openfalcon-audio.log';

// Try to load ws — required for WebSocket support
let WebSocketServer = null;
try {
  WebSocketServer = require('ws').WebSocketServer;
} catch (e) {
  console.error('ws module not installed. Run: npm install ws');
  // Continue without WS — audio streaming still works
}

// ---------- Logging ----------
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stdout.write(line);
  try { fs.appendFileSync(LOG_FILE, line); } catch {}
}

// ---------- Playback state tracking ----------
//
// FPP's /api/fppd/status returns the current_sequence + current_position.
// We poll it and broadcast updates. The "position" is in seconds since the
// sequence started.
const state = {
  sequence: null,           // current sequence name (without extension)
  mediaName: null,          // current media filename (e.g. "Wizards.mp3")
  position: 0,              // seconds elapsed in the current track
  trackDuration: 0,         // total length in seconds
  lastUpdate: 0,            // ms timestamp of last update
};

async function pollFppStatus() {
  try {
    const res = await fetch(`${FPP_HOST}/api/fppd/status`, { signal: AbortSignal.timeout(2000) });
    if (!res.ok) return;
    const status = await res.json();

    // FPP exposes current_sequence (filename), current_song (media file),
    // seconds_played, and seconds_remaining. Different FPP versions vary;
    // try multiple field names.
    const seqRaw = status.current_sequence || status.currentSequence || '';
    const mediaRaw = status.current_song || status.currentSong || status.current_audio || '';
    const playedSec = parseFloat(
      status.seconds_played !== undefined ? status.seconds_played :
      (status.secondsPlayed !== undefined ? status.secondsPlayed : 0)
    ) || 0;
    const remainingSec = parseFloat(
      status.seconds_remaining !== undefined ? status.seconds_remaining :
      (status.secondsRemaining !== undefined ? status.secondsRemaining : 0)
    ) || 0;

    // Strip extensions for sequence name
    const sequence = seqRaw ? seqRaw.replace(/\.[^.]+$/, '') : null;
    const mediaName = mediaRaw || null;

    // Detect track change
    const trackChanged = state.sequence !== sequence;

    state.sequence = sequence;
    state.mediaName = mediaName;
    state.position = playedSec;
    state.trackDuration = playedSec + remainingSec;
    state.lastUpdate = Date.now();

    if (trackChanged) {
      log(`Track changed → ${sequence || '(idle)'}  media=${mediaName || '-'}  duration=${state.trackDuration.toFixed(1)}s`);
    }

    broadcast();
  } catch (err) {
    // Don't spam logs — FPP can be briefly unreachable during sequence transitions
    if (Math.random() < 0.05) log(`Poll error: ${err.message}`);
  }
}

// ---------- WebSocket broadcasting ----------
const wsClients = new Set();
function broadcast() {
  if (wsClients.size === 0) return;
  const payload = JSON.stringify({
    type: 'sync',
    sequence: state.sequence,
    mediaName: state.mediaName,
    position: state.position,
    trackDuration: state.trackDuration,
    serverTimestamp: Date.now(),
  });
  for (const ws of wsClients) {
    if (ws.readyState === 1) {
      try { ws.send(payload); } catch {}
    }
  }
}

// ---------- HTTP server ----------
function safeMediaPath(filename) {
  // Reject anything path-traversal-y. Filenames must not contain / or \ or ..
  if (!filename || filename.includes('..') || filename.includes('/') || filename.includes('\\')) return null;
  const p = path.join(MEDIA_ROOT, filename);
  // Final safety check — resolved path must be under MEDIA_ROOT
  if (!p.startsWith(MEDIA_ROOT + path.sep) && p !== MEDIA_ROOT) return null;
  return p;
}

function getContentType(ext) {
  const map = {
    '.mp3': 'audio/mpeg',
    '.m4a': 'audio/mp4',
    '.ogg': 'audio/ogg',
    '.oga': 'audio/ogg',
    '.opus': 'audio/opus',
    '.flac': 'audio/flac',
    '.wav': 'audio/wav',
    '.aac': 'audio/aac',
  };
  return map[ext.toLowerCase()] || 'audio/mpeg';
}

const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);

  // CORS — viewer pages may be served from a different origin
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Range');
  res.setHeader('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  // ---- Health check ----
  if (parsed.pathname === '/health') {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ ok: true, version: '0.1.0' }));
    return;
  }

  // ---- Now-playing snapshot (REST fallback for browsers without WS) ----
  if (parsed.pathname === '/now') {
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'no-store');
    // Compute live position by adding time-since-last-update to stored position
    const driftMs = Date.now() - state.lastUpdate;
    const livePosition = state.position + (driftMs / 1000);
    res.end(JSON.stringify({
      sequence: state.sequence,
      mediaName: state.mediaName,
      position: state.lastUpdate ? Math.max(0, Math.min(livePosition, state.trackDuration)) : 0,
      trackDuration: state.trackDuration,
      serverTimestamp: Date.now(),
    }));
    return;
  }

  // ---- Audio streaming ----
  if (parsed.pathname.startsWith('/audio/')) {
    const filename = decodeURIComponent(parsed.pathname.slice('/audio/'.length));
    const filepath = safeMediaPath(filename);
    if (!filepath) {
      res.writeHead(400);
      res.end('Bad path');
      return;
    }

    fs.stat(filepath, (err, stat) => {
      if (err) {
        res.writeHead(404);
        res.end('Not found');
        return;
      }
      const ext = path.extname(filepath);
      const contentType = getContentType(ext);
      const total = stat.size;
      const range = req.headers.range;

      // Honor Range requests — this is what makes seek work
      if (range) {
        const m = /^bytes=(\d+)-(\d+)?$/.exec(range);
        if (!m) { res.writeHead(416); res.end(); return; }
        const start = parseInt(m[1], 10);
        const end = m[2] ? parseInt(m[2], 10) : total - 1;
        if (start >= total || end >= total || start > end) {
          res.writeHead(416, { 'Content-Range': `bytes */${total}` });
          res.end();
          return;
        }
        const length = end - start + 1;
        res.writeHead(206, {
          'Content-Type': contentType,
          'Content-Length': length,
          'Content-Range': `bytes ${start}-${end}/${total}`,
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
        });
        if (req.method === 'HEAD') { res.end(); return; }
        fs.createReadStream(filepath, { start, end }).pipe(res);
      } else {
        // No range — send whole file with proper Content-Length so browser knows it's seekable
        res.writeHead(200, {
          'Content-Type': contentType,
          'Content-Length': total,
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'no-cache',
        });
        if (req.method === 'HEAD') { res.end(); return; }
        fs.createReadStream(filepath).pipe(res);
      }
    });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

// ---------- WebSocket setup ----------
if (WebSocketServer) {
  const wss = new WebSocketServer({ server, path: '/sync' });
  wss.on('connection', (ws) => {
    wsClients.add(ws);
    log(`WS connect (${wsClients.size} clients)`);
    ws.on('close', () => {
      wsClients.delete(ws);
      log(`WS disconnect (${wsClients.size} clients)`);
    });
    ws.on('error', () => { wsClients.delete(ws); });
    // Send current state immediately on connect
    if (state.sequence) {
      try {
        ws.send(JSON.stringify({
          type: 'sync',
          sequence: state.sequence,
          mediaName: state.mediaName,
          position: state.position,
          trackDuration: state.trackDuration,
          serverTimestamp: Date.now(),
        }));
      } catch {}
    }
  });
}

// ---------- Lifecycle ----------
server.listen(PORT, '0.0.0.0', () => {
  log(`OpenFalcon audio daemon listening on :${PORT}  media=${MEDIA_ROOT}  fpp=${FPP_HOST}`);
});
setInterval(pollFppStatus, POLL_INTERVAL_MS);
pollFppStatus();

function shutdown(signal) {
  log(`Got ${signal}, shutting down`);
  for (const ws of wsClients) { try { ws.close(); } catch {} }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 2000); // hard exit
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
