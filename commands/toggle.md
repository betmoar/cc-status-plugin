---
description: Enable or disable a cc-status segment by plugin name. Turns a discovered segment on or off in the opt-in config.
argument-hint: <plugin-name> <on|off>  e.g. cc-proxy on
allowed-tools: Bash
disable-model-invocation: true
---

# Toggle a cc-status segment

Requested: **$ARGUMENTS**

1. Parse `$ARGUMENTS` into a plugin `<name>` and a state (`on`/`off`; also accept
   `enable`/`disable`, `1`/`0`). If either is missing or unrecognized, run
   `bash "$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh" list` so the user can see valid
   names and their current states, then stop.
2. Map the state to the subcommand and run exactly one of:

   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh" enable  <name>
   bash "$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh" disable <name>
   ```

3. Confirm in one line using the script's output (e.g. "enabled cc-proxy — it will
   appear on the bar at the next render"). A name that isn't discovered is still
   written to the config (it takes effect if that plugin is installed later); if the
   user seems to have typo'd a name, show them `list`.

Only `segmentctl.sh` writes the config — never edit `~/.claude/cc-status/segments`
directly.
