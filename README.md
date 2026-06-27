# cc-status

The shared **statusline framework** for the betmoar Claude Code plugin fleet.

Claude Code allows exactly one `statusLine` command. cc-status is that command: it
**discovers** every installed plugin that ships a segment manifest, **runs** the ones
you enabled, and **joins** their output with ` | ` onto one bar. Adding a plugin to
the statusline never edits cc-status — the plugin just ships a manifest.

```
claude 5h:7% ~2h | glm[pro] 5h:9% ~4h | ctx[1M] 12%·45
└─ cc-proxy ──────────────────────┘   └─ cc-reload ──┘
```

## Opt-in by design

Every fleet plugin still works **standalone** — install just cc-proxy and you get its
quota bar; just cc-reload and you get context occupancy. cc-status is for when you run
the suite and want them composed onto the single statusline slot. Running its setup is
the act of adopting it.

## Install & set up

Install from the betmoar marketplace, then:

```
/cc-status:setup
```

Setup wires `~/.claude/settings.json` to the cc-status composer and seeds
`~/.claude/cc-status/segments` with every discovered segment **enabled** — so the bar
immediately matches your composed view. Tune from there.

## Managing segments

| Command | Does |
|---|---|
| `/cc-status:list` | List discovered segments: on/off, order, renderer |
| `/cc-status:toggle <name> on\|off` | Enable/disable a segment |
| `/cc-status:order <name> <n>` | Set left-to-right order (lower = further left) |

A plugin you install later shows up in `/cc-status:list` as **discovered but off**
until you toggle it on (opt-in).

## For plugin authors

Make your plugin appear on the bar with two additions — see
[`docs/segment-contract.md`](docs/segment-contract.md) or the `adding-a-segment`
skill:

1. Ship `.claude-plugin/statusline.json`: `{ "name": "...", "render": "...", "order": N }`
2. Write a renderer: reads session JSON on stdin, prints one segment, prints nothing
   when it has nothing.

cc-status keeps the newest installed version of each plugin and skips orphaned cache
dirs, so segments never double up.

## How it works

The composer (`scripts/cc-statusline.sh`) self-relocates to the newest cached
cc-status version, reads the session JSON once, discovers manifests, resolves them
against the opt-in config, fans the same stdin to each enabled renderer, and joins
non-empty results. It degrades at every step — a missing/disabled/empty/errored
segment is skipped; nothing left renders a clean empty bar. It never crashes the
statusline.

Config is mutated only by `scripts/segmentctl.sh` (deterministic bash); the slash
commands and setup skill invoke it — nothing guesses edits to your settings.

## Layout

```
.claude-plugin/plugin.json
scripts/
  cc-statusline.sh     # composer: discover → resolve → fan-out → join
  segmentctl.sh        # config read/mutate (only writer of the segments file)
commands/              # /cc-status:list, :toggle, :order
skills/
  setup/               # wire settings.json + seed config
  adding-a-segment/    # author docs: how a plugin ships a segment
docs/segment-contract.md
tests/test-composer.sh # fake cache + fake session JSON; discovery/order/opt-in/join
```

## Tests

```bash
bash tests/test-composer.sh
```

## License

MIT
