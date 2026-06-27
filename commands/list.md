---
description: List cc-status segments — every discovered plugin segment, whether it is on or off, its order, and its renderer path.
argument-hint: (no arguments)
allowed-tools: Bash
disable-model-invocation: true
---

# cc-status segment roster

Show the user every plugin segment cc-status discovered and its current state.

Execute:

```bash
CTL="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh}"
[ -f "$CTL" ] || CTL="$(ls -d ~/.claude/plugins/cache/*/cc-status/*/scripts/segmentctl.sh 2>/dev/null | sort -V | tail -1)"
[ -f "$CTL" ] || { echo "cc-status: segmentctl.sh not found — is the cc-status plugin installed? Run /cc-status:setup." >&2; exit 1; }
bash "$CTL" list
```

Present the script's stdout **verbatim** — it is already formatted (one line per
segment: `on/off  order=N  name  renderer-path`). Do not summarize or reword it.

If it prints `(no segment manifests discovered …)`, tell the user no installed
plugin ships a `.claude-plugin/statusline.json` manifest yet — cc-status has nothing
to compose until one does. Point them at `/cc-status:setup` if they have not run it,
and at the `adding-a-segment` skill if they are developing a plugin.
