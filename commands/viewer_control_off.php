#!/usr/bin/env php
<?php
// OpenFalcon — Turn Viewer Control Off
$skipJSsettings = true;
include_once "/opt/fpp/www/config.php";
include_once "/opt/fpp/www/common.php";

$pluginName = "openfalcon";
$pluginConfigFile = $settings['configDirectory'] . "/plugin." . $pluginName;
$pluginSettings = @parse_ini_file($pluginConfigFile);

if (!$pluginSettings) exit(1);

$serverUrl = rtrim(urldecode($pluginSettings['serverUrl'] ?? ''), '/');
$showToken = urldecode($pluginSettings['showToken'] ?? '');

if (empty($serverUrl) || empty($showToken)) exit(1);

$payload = json_encode(['mode' => 'OFF']);
$options = [
    'http' => [
        'method'        => 'POST',
        'timeout'       => 10,
        'content'       => $payload,
        'ignore_errors' => true,
        'header'        => implode("\r\n", [
            "Authorization: Bearer $showToken",
            "Content-Type: application/json",
        ]),
    ],
];
$context = stream_context_create($options);
@file_get_contents($serverUrl . '/api/plugin/viewer-mode', false, $context);
?>
