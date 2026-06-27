---
name: adding-a-segment
description: How a Claude Code plugin ships a statusline segment that cc-status can compose. Use when developing a plugin that should appear on the cc-status bar — covers the .claude-plugin/statusline.json manifest, the renderer contract (stdin session JSON in, one segment out), ordering, and graceful-empty behavior.
---

# Adding a cc-status segment to your plugin

cc-status is the single `statusLine` composer for the fleet. Your plugin joins the
bar by shipping two things; cc-status discovers them automatically. You never edit
cc-status, and your plugin still works standalone (wire your renderer directly into
`settings.json` for users who don't run cc-status).

## 1. Ship a manifest

Add `.claude-plugin/statusline.json`, a sibling of your `plugin.json`:

```json
{ "name": "your-plugin", "render": "scripts/statusline.sh", "order": 30 }
```

- **`name`** — your plugin name. This is the key users toggle (`/cc-status:toggle
  your-plugin on`). Match your `plugin.json` `name`.
- **`render`** — path to your renderer, RELATIVE to the plugin root. Any language.
- **`order`** — ascending sort key; lower sits further left. Omit to default to 50.
  Pick a value that gives a sensible left-to-right reading order across the fleet
  (e.g. cc-proxy=10 quota, cc-reload=20 context). Users can override per-install.

cc-status keeps the **newest installed version** of each plugin (semantic sort) and
skips cache dirs marked `.orphaned_at`, so stale versions never double up.

## 2. Write the renderer to the contract

Your renderer is invoked once per statusline render (~every 300ms). The contract:

- **Input:** the live Claude Code session JSON arrives on **stdin** (the same schema
  the native `statusLine` command receives — `context_window`, `rate_limits`,
  `workspace`, `model`, etc.). Read all of stdin, parse what you need.
- **Output:** print **one** segment to stdout. ANSI color is allowed. No trailing
  newline needed. Keep it short — it shares a single line with other segments.
- **Empty case:** when you have nothing to show (no data yet, a missing dependency,
  an unconfigured feature), print **nothing** and `exit 0`. cc-status omits empty
  segments with no dangling ` | ` separator. Never print a placeholder.
- **Never block:** statusline renders are frequent. Cache network/expensive work
  (write a short-TTL cache file under a temp dir) and return fast. A renderer that
  errors is silently skipped, but a slow one stalls the whole bar.

Renderer dispatch is by extension: `.js`/`.mjs` → `node`, `.py` → `python3`,
everything else → `bash`. Your script need not be `chmod +x`.

### Minimal bash renderer

```bash
#!/usr/bin/env bash
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0          # dependency missing -> render nothing
IN="$(cat)"
pct="$(printf '%s' "$IN" | jq -r '.context_window.used_percentage // empty')"
[ -n "$pct" ] || exit 0                            # no data yet -> render nothing
printf 'ctx %s%%' "${pct%%.*}"
```

## 3. Test it standalone

Feed a fake session JSON straight to your renderer:

```bash
echo '{"context_window":{"used_percentage":12.5}}' | bash scripts/statusline.sh
```

Then, with cc-status installed, the user enables you:

```
/cc-status:toggle your-plugin on
/cc-status:list                  # confirms you're listed, on, and in order
```

## Design notes

- **Standalone-first.** Don't make your plugin depend on cc-status. Ship your own
  setup that wires your renderer directly for solo users; the manifest is purely
  additive — it only matters when cc-status is the active composer.
- **One segment, one concern.** Keep each plugin's segment to its own domain
  (quota, context, build status). Composition is cc-status's job, not yours.
- **Color sparingly.** Reserve red for genuinely actionable states; the bar gets
  crowded with several segments.
