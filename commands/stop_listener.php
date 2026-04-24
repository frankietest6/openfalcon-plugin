#!/usr/bin/env php
<?php
$skipJSsettings = true;
include_once "/opt/fpp/www/config.php";
include_once "/opt/fpp/www/common.php";
$pluginName = "openfalcon";

WriteSettingToFile("listenerEnabled", urlencode("false"), $pluginName);
?>
