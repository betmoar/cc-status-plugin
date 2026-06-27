---
description: Set a cc-status segment's left-to-right order. Lower numbers sit further left on the bar; overrides the plugin's manifest default.
argument-hint: <plugin-name> <number>  e.g. cc-reload 5
allowed-tools: Bash
disable-model-invocation: true
---

# Reorder a cc-status segment

Requested: **$ARGUMENTS**

1. Parse `$ARGUMENTS` into a plugin `<name>` and a non-negative integer `<n>`. If
   either is missing or `<n>` is not a number, run
   `bash "$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh" list` to show current names and
   orders, then stop.
2. Run:

   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh" order <name> <n>
   ```

3. Confirm in one line (e.g. "cc-reload → order 5; it moves left of segments with a
   higher number"). Segments render ascending by order; ties fall back to discovery
   order. This override beats the manifest's default `order` for this install only.

Only `segmentctl.sh` writes the config — never edit `~/.claude/cc-status/segments`
directly.
