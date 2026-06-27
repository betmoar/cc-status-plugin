#!/usr/bin/env bash
#
# cc-status composer — the single statusLine command for the betmoar plugin fleet.
#
# Claude Code allows exactly ONE statusLine command. cc-status is that command: it
# DISCOVERS every installed plugin that ships a segment manifest, RUNS the ones the
# user enabled, and JOINS their output with " | ". Adding a plugin to the bar never
# edits this file — the plugin just ships a manifest.
#
# Wire as the single statusLine command in ~/.claude/settings.json (the setup skill
# does this for you):
#   "statusLine": { "type": "command",
#     "command": "bash /ABS/PATH/cc-status/scripts/cc-statusline.sh" }
#
# CONTRACT (plugin side): a participating plugin ships, next to its plugin.json:
#   .claude-plugin/statusline.json  =  { "name": "...", "render": "rel/path", "order": N }
#   - render: path RELATIVE to the plugin root; any language; reads session JSON on
#     stdin, prints ONE segment (ANSI ok), prints nothing + exit 0 when it has nothing.
#   - order:  ascending sort key (lower = further left). Default 50 when absent.
#
# CONFIG (user side, opt-in): ~/.claude/cc-status/segments, lines "name=enabled:order".
#   A discovered plugin with NO entry is OFF. See segmentctl.sh.
#
# Self-relocation: when this copy lives in the versioned plugin cache
# (.../cc-status/<ver>/scripts), re-exec the composer from the NEWEST installed
# cc-status version, so a version-pinned settings.json path keeps tracking new
# installs without editing settings.json. A checkout OUTSIDE the cache (a dev tree)
# is left alone — that path was chosen deliberately.
#
# Degrades gracefully at every step: missing manifest -> skip; disabled -> skip;
# renderer empty or errored -> skip; nothing left -> print nothing (clean bar).
# Never crashes the statusline.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- self-relocation: hand off to the newest cached cc-status -----------------
case "$HERE" in
  */.claude/plugins/cache/*/cc-status/*/scripts)
    CACHE_ROOT="${HERE%/cc-status/*}"   # .../<owner> dir holding cc-status/<ver>
    NEWEST="$(ls -d "$CACHE_ROOT"/cc-status/*/scripts/cc-statusline.sh 2>/dev/null | sort -V | tail -1)"
    # Only hand off to a DIFFERENT, readable file — never re-exec ourselves (loop).
    if [ -n "$NEWEST" ] && [ "$NEWEST" != "$HERE/cc-statusline.sh" ] && [ -f "$NEWEST" ]; then
      exec bash "$NEWEST"
    fi
    ;;
esac

# Read the session JSON once; hand the SAME bytes to every renderer.
IN="$(cat)"

CONFIG="${CC_STATUS_CONFIG:-$HOME/.claude/cc-status/segments}"
CACHE="${CC_STATUS_CACHE:-$HOME/.claude/plugins/cache}"

# --- config lookup: is <name> enabled? what order override? -------------------
# Reads the opt-in config. Echoes "<enabled>\t<order>" where enabled is 0/1 and
# order is the override or empty. Absent from config => disabled (opt-in model).
config_lookup() {
  local name="$1" line val enabled order
  [ -f "$CONFIG" ] || { printf '0\t'; return; }
  # Last matching line wins; tolerate surrounding whitespace.
  line="$(grep -E "^[[:space:]]*${name}[[:space:]]*=" "$CONFIG" 2>/dev/null | tail -1)"
  [ -n "$line" ] || { printf '0\t'; return; }
  val="${line#*=}"                       # right of first '='
  val="${val%%#*}"                       # strip trailing comment
  val="$(printf '%s' "$val" | tr -d '[:space:]')"
  enabled="${val%%:*}"                    # left of ':'
  order=""; case "$val" in *:*) order="${val#*:}";; esac
  case "$enabled" in 1|true|on|yes) enabled=1;; *) enabled=0;; esac
  [[ "$order" =~ ^[0-9]+$ ]] || order=""
  printf '%s\t%s' "$enabled" "$order"
}

# --- discovery: newest non-orphaned manifest per plugin name ------------------
# Emits one TSV row per ENABLED segment: "<effective_order>\t<renderer_abs_path>".
# Source rows are sorted (name asc, version desc) so the FIRST row seen per name is
# the newest version REGARDLESS of owner dir — a cross-owner same-name plugin can't
# let a lexically-earlier owner shadow a higher version.
discover() {
  local name ver ver_root manifest render order_m abs enabled order_o eff
  local seen=" "
  while IFS=$'\t' read -r name ver ver_root; do
    [ -n "$name" ] || continue
    case "$seen" in *" $name "*) continue;; esac          # already took newest
    # This IS the newest version of <name>; commit to it. If its renderer is
    # missing we skip the SEGMENT — never silently downgrade to an older version
    # (that would lie about which version is running). Mark seen either way.
    seen="$seen$name "
    manifest="$ver_root/.claude-plugin/statusline.json"
    render="$(_json_field "$manifest" render)"
    [ -n "$render" ] || continue
    abs="$ver_root/$render"
    [ -f "$abs" ] || continue                             # newest's renderer gone
    IFS=$'\t' read -r enabled order_o < <(config_lookup "$name")
    [ "$enabled" = "1" ] || continue
    order_m="$(_json_field "$manifest" order)"
    [[ "$order_m" =~ ^[0-9]+$ ]] || order_m=""
    eff="${order_o:-${order_m:-50}}"                      # config > manifest > 50
    printf '%s\t%s\n' "$eff" "$abs"
  done < <(_discover_rows)
}

# All non-orphaned manifests as "name<TAB>version<TAB>ver_root", sorted name-asc
# then version-desc so the first row per name is the newest version, owner-agnostic.
# Path shape: <cache>/<owner>/<plugin>/<ver>/.claude-plugin/statusline.json
_discover_rows() {
  local manifest ver_root ver name
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    ver_root="${manifest%/.claude-plugin/statusline.json}"
    [ -f "$ver_root/.orphaned_at" ] && continue           # dead cache dir
    ver="$(basename "$ver_root")"
    name="$(_json_field "$manifest" name)"
    [ -n "$name" ] || name="$(basename "$(dirname "$ver_root")")"
    printf '%s\t%s\t%s\n' "$name" "$ver" "$ver_root"
  done < <(ls -d "$CACHE"/*/*/*/.claude-plugin/statusline.json 2>/dev/null) \
    | sort -t$'\t' -k1,1 -k2,2Vr
}

# Minimal JSON scalar extractor for a flat manifest: _json_field <file> <key>.
# Manifests are tiny and flat ({name,render,order}); a jq dependency is avoided so
# the composer runs even where jq is absent. Matches "key": "value" or "key": N.
_json_field() {
  local file="$1" key="$2"
  sed -n -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p; s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$file" 2>/dev/null | head -1
}

# Dispatch a renderer by extension: .js/.mjs -> node, .py -> python3, else bash
# (covers .sh and any executable text). Keeps the contract language-agnostic
# without depending on the renderer being chmod +x inside the read-only cache.
_run() {
  case "$1" in
    *.js|*.mjs) command -v node >/dev/null 2>&1 && node "$1" ;;
    *.py)       command -v python3 >/dev/null 2>&1 && python3 "$1" ;;
    *)          bash "$1" ;;
  esac
}

# --- render + join -----------------------------------------------------------
OUT=""
while IFS=$'\t' read -r _order renderer; do
  [ -n "$renderer" ] || continue
  part="$(printf '%s' "$IN" | _run "$renderer" 2>/dev/null)"
  [ -n "$part" ] || continue
  if [ -z "$OUT" ]; then OUT="$part"; else OUT="$OUT | $part"; fi
done < <(discover | sort -n -k1,1)

printf '%s' "$OUT"
