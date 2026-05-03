<?php
// ShowPilot config bridge. FPP's plugin-settings REST endpoints have changed
// across versions; WriteSettingToFile has stayed compatible with the plugin
// config file format the listener already reads.
header('Cache-Control: no-store');
$skipJSsettings = true;
include_once "/opt/fpp/www/config.php";
include_once "/opt/fpp/www/common.php";

$pluginName = "showpilot";
$pluginConfigFile = $settings['configDirectory'] . "/plugin." . $pluginName;

$allowedKeys = array(
    'serverUrl' => true,
    'showToken' => true,
    'remotePlaylist' => true,
    'interruptSchedule' => true,
    'requestFetchTime' => true,
    'additionalWaitTime' => true,
    'fppStatusCheckTime' => true,
    'heartbeatIntervalSec' => true,
    'verboseLogging' => true,
    'listenerEnabled' => true,
    'listenerRestarting' => true,
);

function respondJson($code, $payload) {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($payload);
    exit;
}

function ensureConfigFile($path) {
    if (!file_exists($path)) {
        @touch($path);
        @chmod($path, 0644);
    }
    return file_exists($path) && is_readable($path);
}

$action = $_GET['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($method === 'GET' && $action === 'raw') {
    if (!ensureConfigFile($pluginConfigFile)) {
        http_response_code(500);
        header('Content-Type: text/plain');
        echo 'Could not read plugin config';
        exit;
    }
    header('Content-Type: text/plain');
    echo file_get_contents($pluginConfigFile);
    exit;
}

if ($method !== 'POST') {
    respondJson(405, array('error' => 'Method not allowed'));
}

$body = file_get_contents('php://input');
$params = array();
parse_str($body, $params);

if ($action === 'raw') {
    $content = $params['content'] ?? '';
    if (trim($content) === '') {
        respondJson(400, array('error' => 'Empty config'));
    }
    $ok = @file_put_contents($pluginConfigFile, $content);
    @chmod($pluginConfigFile, 0644);
    if ($ok === false) {
        respondJson(500, array('error' => 'Could not write plugin config'));
    }
    respondJson(200, array('ok' => true));
}

$key = $params['key'] ?? '';
$value = $params['value'] ?? '';

if (!isset($allowedKeys[$key])) {
    respondJson(400, array('error' => 'Invalid setting key'));
}

if (!ensureConfigFile($pluginConfigFile)) {
    respondJson(500, array('error' => 'Could not create plugin config'));
}

WriteSettingToFile($key, urlencode($value), $pluginName);
respondJson(200, array('ok' => true));
