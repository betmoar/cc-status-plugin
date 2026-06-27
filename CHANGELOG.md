# Changelog

All notable changes to cc-status are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-06-27

### Fixed

- `/cc-status:list`, `:toggle`, `:order` and the setup skill failed with **exit 127**
  when `CLAUDE_PLUGIN_ROOT` was not exported into the shell running the command
  blocks — the path collapsed to `/scripts/segmentctl.sh`. Each now resolves the
  script itself: use `$CLAUDE_PLUGIN_ROOT` when set, otherwise glob the newest cached
  install (the same fallback the setup skill already used for the composer path).
  If neither location resolves, the command now exits with an actionable error
  instead of a confusing `bash: : No such file or directory`.

## [0.1.0] - 2026-06-27

### Added

- Initial release: the shared `statusLine` composer for the betmoar plugin fleet.
- `scripts/cc-statusline.sh` — discovers per-plugin `.claude-plugin/statusline.json`
  manifests, runs enabled segments, joins their output with ` | `. Self-relocates to
  the newest cached version; degrades gracefully (missing/disabled/empty/errored
  segments skipped; never crashes the bar).
- `scripts/segmentctl.sh` — sole writer of the opt-in config
  (`~/.claude/cc-status/segments`): `list`, `enable`, `disable`, `order`, `seed`,
  `status`.
- Slash commands: `/cc-status:list`, `/cc-status:toggle`, `/cc-status:order`.
- Skills: `setup` (wire settings.json + seed config), `adding-a-segment` (author
  guide).
- `docs/segment-contract.md` — the manifest + renderer contract.
- `tests/test-composer.sh` — fake-cache discovery/order/opt-in/join coverage.

[0.1.1]: https://github.com/betmoar/cc-status-plugin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/betmoar/cc-status-plugin/releases/tag/v0.1.0
