#!/usr/bin/env bash
#
# segmentctl — deterministic read/mutate of the cc-status opt-in config.
#
# The config is ~/.claude/cc-status/segments, one line per plugin:
#   name=enabled:order      enabled in {0,1}; ":order" optional (falls back to the
#                           plugin's manifest order, then 50). Comments: '#...'.
# A discovered plugin with NO line is OFF (opt-in). This script is the ONLY writer
# of that file — slash commands invoke it; nothing LLM-guesses edits to it.
#
# Subcommands:
#   list                 discovered segments: name, on/off, effective order, renderer
#   enable  <name>       set <name>=1 (preserving any order)
#   disable <name>       set <name>=0 (preserving any order)
#   order   <name> <n>   set <name>'s order override to <n>
#   seed                 write every currently-discovered segment as enabled
#                          (the setup migration bridge; never clobbers existing lines)
#   status               one-line summary: "<enabled> enabled, <discovered> discovered"
#
set -uo pipefail

CONFIG="${CC_STATUS_CONFIG:-$HOME/.claude/cc-status/segments}"
CACHE="${CC_STATUS_CACHE:-$HOME/.claude/plugins/cache}"

# ---- shared manifest helpers (kept in sync with cc-statusline.sh) ------------
_json_field() {
  local file="$1" key="$2"
  sed -n -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p; s/.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p" "$file" 2>/dev/null | head -1
}

# Emit "name<TAB>manifest_order<TAB>renderer_abs" for the newest non-orphaned
# manifest of each plugin. Mirrors the composer's discovery, minus config.
# manifest_order is EMPTY when the manifest declares none (so seed can avoid
# freezing a synthetic order — see cmd_seed). Rows sorted name-asc/version-desc
# so the first per name is the newest version, owner-agnostic.
_discover_all() {
  local name ver ver_root manifest render order seen=" "
  while IFS=$'\t' read -r name ver ver_root; do
    [ -n "$name" ] || continue
    case "$seen" in *" $name "*) continue;; esac
    seen="$seen$name "
    manifest="$ver_root/.claude-plugin/statusline.json"
    render="$(_json_field "$manifest" render)"
    [ -n "$render" ] || continue
    [ -f "$ver_root/$render" ] || continue
    order="$(_json_field "$manifest" order)"
    [[ "$order" =~ ^[0-9]+$ ]] || order=""        # empty => manifest declares none
    printf '%s\t%s\t%s\n' "$name" "$order" "$ver_root/$render"
  done < <(_seg_rows)
}

# "name<TAB>version<TAB>ver_root" for every non-orphaned manifest, sorted name-asc
# then version-desc (owner-agnostic newest-first per name).
_seg_rows() {
  local manifest ver_root ver name
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    ver_root="${manifest%/.claude-plugin/statusline.json}"
    [ -f "$ver_root/.orphaned_at" ] && continue
    ver="$(basename "$ver_root")"
    name="$(_json_field "$manifest" name)"
    [ -n "$name" ] || name="$(basename "$(dirname "$ver_root")")"
    printf '%s\t%s\t%s\n' "$name" "$ver" "$ver_root"
  done < <(ls -d "$CACHE"/*/*/*/.claude-plugin/statusline.json 2>/dev/null) \
    | sort -t$'\t' -k1,1 -k2,2Vr
}

# Parsed view of one config line for <name>: echoes "<enabled>\t<order>" (order
# possibly empty). Absent => "0\t".
_config_line() {
  local name="$1" line val enabled order
  [ -f "$CONFIG" ] || { printf '0\t'; return; }
  line="$(grep -E "^[[:space:]]*${name}[[:space:]]*=" "$CONFIG" 2>/dev/null | tail -1)"
  [ -n "$line" ] || { printf '0\t'; return; }
  val="${line#*=}"; val="${val%%#*}"; val="$(printf '%s' "$val" | tr -d '[:space:]')"
  enabled="${val%%:*}"; order=""; case "$val" in *:*) order="${val#*:}";; esac
  case "$enabled" in 1|true|on|yes) enabled=1;; *) enabled=0;; esac
  printf '%s\t%s' "$enabled" "$order"
}

_ensure_config() {
  mkdir -p "$(dirname "$CONFIG")"
  [ -f "$CONFIG" ] || {
    printf '# cc-status segments — "name=enabled:order" (order optional).\n# Edit via /cc-status-toggle and /cc-status-order, not by hand.\n' > "$CONFIG"
  }
}

# Upsert <name> with explicit enabled and order (order may be empty -> bare flag).
_set_line() {
  local name="$1" enabled="$2" order="$3" newline tmp
  _ensure_config
  if [ -n "$order" ]; then newline="${name}=${enabled}:${order}"; else newline="${name}=${enabled}"; fi
  # Temp file MUST be on the same filesystem as $CONFIG so the mv is an atomic
  # same-fs rename, not a cross-volume copy+unlink ($TMPDIR may be another volume).
  tmp="$(mktemp "${CONFIG}.XXXXXX")" || return 1
  if grep -qE "^[[:space:]]*${name}[[:space:]]*=" "$CONFIG" 2>/dev/null; then
    # Replace the existing line in place.
    awk -v n="$name" -v repl="$newline" '
      $0 ~ "^[[:space:]]*" n "[[:space:]]*=" { print repl; next } { print }
    ' "$CONFIG" > "$tmp"
  else
    cat "$CONFIG" > "$tmp"; printf '%s\n' "$newline" >> "$tmp"
  fi
  mv "$tmp" "$CONFIG"
}

cmd_list() {
  local any=0 name m_order renderer enabled c_order eff state
  while IFS=$'\t' read -r name m_order renderer; do
    [ -n "$name" ] || continue
    any=1
    IFS=$'\t' read -r enabled c_order < <(_config_line "$name")
    eff="${c_order:-${m_order:-50}}"               # config > manifest > 50 (display)
    [ "$enabled" = "1" ] && state="on " || state="off"
    printf '%s  order=%-3s  %s  %s\n' "$state" "$eff" "$name" "$renderer"
  done < <(_discover_all | sort -t$'\t' -k2,2n)
  [ "$any" = "1" ] || echo "(no segment manifests discovered under $CACHE)"
}

cmd_enable()  { local o; o="$(_config_line "$1" | cut -f2)"; _set_line "$1" 1 "$o"; echo "enabled $1"; }
cmd_disable() { local o; o="$(_config_line "$1" | cut -f2)"; _set_line "$1" 0 "$o"; echo "disabled $1"; }

cmd_order() {
  [[ "$2" =~ ^[0-9]+$ ]] || { echo "order must be a non-negative integer" >&2; return 2; }
  local e; e="$(_config_line "$1" | cut -f1)"
  _set_line "$1" "$e" "$2"; echo "order $1 -> $2"
}

cmd_seed() {
  local name m_order renderer n=0
  while IFS=$'\t' read -r name m_order renderer; do
    [ -n "$name" ] || continue
    # Never clobber an existing decision; only add missing segments as enabled.
    # Seed with NO order override (bare "name=1") so the plugin's manifest order —
    # including any later bump — stays authoritative. Only an explicit
    # /cc-status:order writes a :override.
    if ! grep -qE "^[[:space:]]*${name}[[:space:]]*=" "$CONFIG" 2>/dev/null; then
      _set_line "$name" 1 ""; n=$((n+1))
    fi
  done < <(_discover_all)
  echo "seeded $n new segment(s) (enabled)"
}

cmd_status() {
  local disc=0 en=0 name _o _r enabled
  while IFS=$'\t' read -r name _o _r; do
    [ -n "$name" ] || continue
    disc=$((disc+1))
    enabled="$(_config_line "$name" | cut -f1)"
    [ "$enabled" = "1" ] && en=$((en+1))
  done < <(_discover_all)
  echo "$en enabled, $disc discovered"
}

case "${1:-}" in
  list)    cmd_list ;;
  enable)  [ -n "${2:-}" ] || { echo "usage: segmentctl enable <name>" >&2; exit 2; }; cmd_enable "$2" ;;
  disable) [ -n "${2:-}" ] || { echo "usage: segmentctl disable <name>" >&2; exit 2; }; cmd_disable "$2" ;;
  order)   [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "usage: segmentctl order <name> <n>" >&2; exit 2; }; cmd_order "$2" "$3" ;;
  seed)    _ensure_config; cmd_seed ;;
  status)  cmd_status ;;
  *) echo "usage: segmentctl {list|enable <name>|disable <name>|order <name> <n>|seed|status}" >&2; exit 2 ;;
esac
