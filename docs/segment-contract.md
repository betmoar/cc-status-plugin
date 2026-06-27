# cc-status segment contract

The interface every plugin implements to appear on the cc-status bar. cc-status
discovers conforming plugins automatically — it is never edited to add one.

## Manifest: `.claude-plugin/statusline.json`

A flat JSON file beside the plugin's `plugin.json`:

```json
{ "name": "cc-reload", "render": "scripts/statusline.sh", "order": 20 }
```

| Field    | Required | Meaning |
|----------|----------|---------|
| `name`   | yes      | Plugin name; the key users toggle. Match `plugin.json` `name`. |
| `render` | yes      | Renderer path, **relative to the plugin root**. Any language. |
| `order`  | no       | Ascending sort key; lower = further left. Defaults to `50`. |

The manifest is parsed without `jq` (a flat-scalar `sed` extractor), so it must stay
flat — `name`/`render` as JSON strings, `order` as a bare integer. No nesting. Keep
keys to `name`/`render`/`order`; the extractor is line-oriented and not a full JSON
parser, so exotic content (escaped quotes, a field value equal to another key name)
is not supported.

## Renderer contract

Invoked once per statusline render (~every 300 ms).

- **Input:** the live session JSON on **stdin** — the same schema Claude Code passes
  to a native `statusLine` command (`context_window`, `rate_limits`, `workspace`,
  `model`, …). Read all of stdin.
- **Output:** exactly **one** segment to stdout. ANSI color allowed. No trailing
  newline required.
- **Empty:** nothing to show → print nothing, `exit 0`. cc-status omits the segment
  with no dangling separator. Never emit a placeholder.
- **Fast + non-blocking:** cache expensive/network work behind a short TTL; return
  immediately. Errors are skipped silently; slowness stalls the whole bar.

## Dispatch

By renderer extension: `.js`/`.mjs` → `node`, `.py` → `python3`, else → `bash`.
The renderer need not be executable.

## Discovery & resolution (what cc-status does)

1. Glob `~/.claude/plugins/cache/*/*/*/.claude-plugin/statusline.json`.
2. Keep the **newest version** per plugin name (`sort -V`); skip dirs with
   `.orphaned_at`.
3. Overlay `~/.claude/cc-status/segments` (the opt-in config): run only enabled
   segments; a discovered plugin with no config line is **off**.
4. Sort ascending by effective order (config override → manifest `order` → 50).
5. Fan the same stdin bytes to each renderer; join non-empty outputs with ` | `.

## Config file: `~/.claude/cc-status/segments`

One line per plugin, `name=enabled:order` (the `:order` override is optional):

```
cc-proxy=1:10
cc-reload=1:20
cc-repete=0:30
```

Written only by `scripts/segmentctl.sh` (via `/cc-status:toggle`, `/cc-status:order`,
and the setup seeder). `enabled` ∈ `{0,1}` (also accepts `on/off/true/false/yes/no`).
Absent line ⇒ off.

## Standalone coexistence

A plugin should still wire its own renderer into `settings.json` for users who do
not run cc-status. The manifest is purely additive: it only takes effect when
cc-status is the active `statusLine`. Both paths reuse the same renderer script.
