<!--
  Param order matters here: nopage=1 MUST come before page=... .

  FPP's plugin-manager "Open" button (10.x beta+, July 2026) resolves a
  plugin's page URL by statically scanning menu/content_menu.inc with a
  substring regex, not a real query-string parser. "nopage=1" itself
  contains the substring "page=1", so if it appears AFTER our real
  page=showpilot_ui.html, the scanner's greedy match latches onto that
  and reports the page as literal "1" instead of showpilot_ui.html —
  plugin.php then 404s with "requesting a page that doesn't exist:
  showpilot/1". Putting nopage first avoids the collision. Confirmed
  against FPP's _PluginExtractPageFromHtml regex before shipping.

  The "plugin=" value below is NOT the same static-text-scan target as
  "page=" above. FPP's real sidebar renderer (list_plugin_entries() in
  www/menu.inc) actually `include_once()`s this file with output
  buffering — so the PHP below runs for real on every page load — while
  the Plugin Manager's separate "Open" button scanner (_PluginGetBestPageUrl
  in www/api/controllers/plugin.php) builds its own "plugin=" from the true
  on-disk directory name and never reads it from here at all; it only
  extracts "page=" from this file. So: safe to compute dynamically, and it
  must be — this is exactly the second place fpp-data#209's v0.13.72
  repoName change broke (the first being every script's hardcoded
  PLUGIN_DIR, fixed in v0.13.74). A hardcoded "showpilot" here is what
  produced "Error with plugin, requesting a page that doesn't exist:
  showpilot/showpilot_ui.html" even after v0.13.74's script fixes were
  live. basename(__DIR__) always resolves to this plugin's actual current
  install directory, so it can never drift from repoName again regardless
  of future renames — content_menu.inc lives at the plugin's own root, so
  no dirname() is needed the way commands/restart_listener.php needs one.
-->
<li><a href="plugin.php?plugin=<?php echo htmlspecialchars(basename(__DIR__)); ?>&nopage=1&page=showpilot_ui.html">ShowPilot Configuration</a></li>
