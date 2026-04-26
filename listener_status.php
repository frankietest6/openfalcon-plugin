<?php
// ShowPilot listener status check — used by config UI to live-update
// the running/stopped banner without a full page refresh.
//
// Uses `pgrep -fa` to get the full command line of matching processes,
// then filters to only those that are actually `php …showpilot_listener.php`
// (and not, e.g., a brief PHP wrapper, the plugin updater, or pgrep itself).
header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate');

$out = @shell_exec("pgrep -fa showpilot_listener.php 2>/dev/null");
$lines = $out ? array_filter(array_map('trim', explode("\n", $out))) : array();

$pids = array();
foreach ($lines as $line) {
    // Format: "<PID> <cmd>"
    $parts = preg_split('/\s+/', $line, 2);
    if (count($parts) < 2) continue;
    $pid = $parts[0];
    $cmd = $parts[1];
    // Only count processes whose command line is `php … showpilot_listener.php`
    if (preg_match('#(^|/)php\s+.*showpilot_listener\.php#', $cmd)) {
        $pids[] = $pid;
    }
}

$running = count($pids) > 0;

echo json_encode([
    'running' => $running,
    'pids' => $pids,
    'checkedAt' => date('c'),
]);
