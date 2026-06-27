---
name: setup
description: One-time setup for the cc-status plugin, run when the user explicitly invokes /cc-status:setup. Wires ~/.claude/settings.json so the cc-status composer becomes the single statusLine, then seeds ~/.claude/cc-status/segments enabling every discovered plugin segment. Use when the user wants to adopt or enable the cc-status statusline.
---

# cc-status setup

One-time wiring so cc-status composes every enabled plugin segment onto Claude
Code's single statusline. Adopting cc-status is opt-in: each plugin still works
standalone with its own renderer; running this skill switches the `statusLine` slot
to the cc-status composer instead.

## What to do

Follow these steps **exactly**. Do not skip any.

### 1. Resolve the composer path

The composer must be referenced by ABSOLUTE path — the `statusLine` command runs
outside plugin context, so `${CLAUDE_PLUGIN_ROOT}` is unavailable *there*. But it
**is** set here, inside this skill, and already points at the running cc-status
install (cache or dev checkout). Resolve it to an absolute path:

```bash
realpath "$CLAUDE_PLUGIN_ROOT/scripts/cc-statusline.sh"
```

Use that value. Only if `$CLAUDE_PLUGIN_ROOT` is somehow unset, fall back to the
newest cached install:

```bash
ls -d ~/.claude/plugins/cache/*/cc-status/*/scripts/cc-statusline.sh 2>/dev/null | sort -V | tail -1
```

If neither resolves, ask the user where `cc-statusline.sh` is and use that absolute
path.

> The composer self-relocates: a path under the versioned cache auto-follows future
> cc-status installs without re-editing settings.json. So pinning the current path
> here is fine — it tracks bumps on its own. (A dev-checkout path is left as-is,
> which is what you want while developing.)

### 2. Seed the opt-in config

Resolve the control script first. `$CLAUDE_PLUGIN_ROOT` is set inside this skill but
not always in the shell that runs these blocks, so fall back to the newest cached
install (same resolution as step 1):

```bash
CTL="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/segmentctl.sh}"
[ -f "$CTL" ] || CTL="$(ls -d ~/.claude/plugins/cache/*/cc-status/*/scripts/segmentctl.sh 2>/dev/null | sort -V | tail -1)"
[ -f "$CTL" ] || { echo "cc-status: segmentctl.sh not found — is the cc-status plugin installed?" >&2; exit 1; }
```

If the resolution block above exits with "segmentctl.sh not found", stop and tell the
user the cc-status install could not be located (mirrors the "If neither resolves…" guidance in step 1).

Run the deterministic seeder (it writes `~/.claude/cc-status/segments`, enabling
every plugin segment currently discovered in the cache, and never clobbers a line
the user already set):

```bash
bash "$CTL" seed
```

Then show the user the resulting roster:

```bash
bash "$CTL" list
```

This is the migration bridge: right after setup the bar matches the composed view
the user had before (all discovered segments on). They tune with `/cc-status:toggle`
and `/cc-status:order` afterward.

### 3. Wire settings.json `statusLine`

Read `~/.claude/settings.json`. Merge this **top-level** key (it is NOT under
`env`), preserving every other existing key unchanged:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash <ABS_PATH from step 1>"
  }
}
```

**If a `statusLine` is already configured** (e.g. the user previously wired
cc-proxy's or cc-reload's renderer directly), this is the intended replacement —
cc-status composes those same segments and more. Show the user the existing command
and the new one, and confirm before overwriting. Do not silently clobber.

Write the file back with 2-space indentation, matching the existing formatting. If
`~/.claude/settings.json` does not exist, create it as valid JSON with just the
`statusLine` key.

### 4. Inform the user

Tell the user, verbatim:

> Setup complete. cc-status is now your statusLine — it composes every enabled
> plugin segment. The bar refreshes on the next render (~within a second). Manage
> segments with `/cc-status:list`, `/cc-status:toggle <name> on|off`, and
> `/cc-status:order <name> <n>`. A plugin you install later appears in
> `/cc-status:list` as discovered-but-off until you toggle it on.

## Important constraints

- **Do not** overwrite unrelated keys in `settings.json`. Merge, never rewrite from
  template.
- **The composer path must be absolute.** `${CLAUDE_PLUGIN_ROOT}` is not set in the
  `statusLine` context.
- **Only `segmentctl.sh` writes the segments config.** Never hand-edit
  `~/.claude/cc-status/segments` from this skill — call the script (step 2).
- A discovered plugin with no config line is OFF by design (opt-in). `seed` turns on
  what exists at setup time; later installs are the user's call.
