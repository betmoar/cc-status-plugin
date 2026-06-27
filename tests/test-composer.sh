#!/usr/bin/env bash
#
# cc-status composer + segmentctl tests. Builds a fake plugin cache and a fake
# session JSON in a temp dir, points the scripts at them via CC_STATUS_CACHE /
# CC_STATUS_CONFIG, and asserts discovery, ordering, opt-in, disable, omit-empty,
# and the join. No network, no real Claude Code, no real ~/.claude.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSER="$HERE/../scripts/cc-statusline.sh"
SEGCTL="$HERE/../scripts/segmentctl.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     expected: %s\n     got:      %s\n' "$1" "$2" "$3"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CACHE="$TMP/cache"
CONFIG="$TMP/segments"
export CC_STATUS_CACHE="$CACHE"
export CC_STATUS_CONFIG="$CONFIG"

SESSION='{"context_window":{"used_percentage":12.5,"context_window_size":1000000},"workspace":{"project_dir":"/x"}}'

# --- fake fleet: alpha (order 10), beta (order 20), gamma (no order -> 50),
#     dead (orphaned, must be skipped), older alpha version (must lose to newer).
mk_plugin() { # owner plugin version render_name order_json body
  local d="$CACHE/$1/$2/$3"
  mkdir -p "$d/.claude-plugin" "$d/scripts"
  printf '%s' "$6" > "$d/scripts/$4"
  if [ -n "$5" ]; then
    printf '{"name":"%s","render":"scripts/%s","order":%s}\n' "$2" "$4" "$5" > "$d/.claude-plugin/statusline.json"
  else
    printf '{"name":"%s","render":"scripts/%s"}\n' "$2" "$4" > "$d/.claude-plugin/statusline.json"
  fi
}

mk_plugin betmoar alpha 0.1.0 seg.sh 10 'printf "ALPHA"'
mk_plugin betmoar beta  0.2.0 seg.sh 20 'printf "BETA"'
mk_plugin betmoar gamma 1.0.0 seg.sh "" 'printf "GAMMA"'
# Empty renderer: prints nothing -> must be omitted with no dangling separator.
mk_plugin betmoar quiet 0.1.0 seg.sh 5  'exit 0'
# Newer alpha version with DIFFERENT output -> newest must win.
mk_plugin betmoar alpha 0.2.0 seg.sh 10 'printf "ALPHA2"'
# Orphaned plugin -> must be skipped even though manifest is valid.
mk_plugin betmoar dead  9.9.9 seg.sh 1  'printf "DEAD"'
touch "$CACHE/betmoar/dead/9.9.9/.orphaned_at"

run_composer() { printf '%s' "$SESSION" | bash "$COMPOSER"; }

echo "== segmentctl discovery =="
# All real plugins discovered (alpha,beta,gamma,quiet) but NOT dead (orphaned).
eq "status: 0 enabled before opt-in" "0 enabled, 4 discovered" "$(bash "$SEGCTL" status)"

echo "== composer: nothing enabled -> empty bar =="
eq "empty when no config" "" "$(run_composer)"

echo "== seed enables all discovered =="
bash "$SEGCTL" seed >/dev/null
eq "status after seed" "4 enabled, 4 discovered" "$(bash "$SEGCTL" status)"

echo "== composer: ordered join, newest-version wins, empty omitted =="
# Order: quiet(5,empty) alpha(10) beta(20) gamma(50). quiet omitted.
eq "ordered join" "ALPHA2 | BETA | GAMMA" "$(run_composer)"

echo "== disable drops a segment cleanly =="
bash "$SEGCTL" disable beta >/dev/null
eq "beta disabled" "ALPHA2 | GAMMA" "$(run_composer)"
eq "status after disable" "3 enabled, 4 discovered" "$(bash "$SEGCTL" status)"

echo "== order override re-sorts =="
bash "$SEGCTL" enable beta >/dev/null
bash "$SEGCTL" order gamma 1 >/dev/null   # gamma now leftmost
eq "gamma reordered to front" "GAMMA | ALPHA2 | BETA" "$(run_composer)"

echo "== opt-in: a discovered-but-unconfigured plugin stays off =="
# Add a new plugin AFTER seed; it has no config line -> must NOT appear.
mk_plugin betmoar delta 0.1.0 seg.sh 15 'printf "DELTA"'
eq "delta discovered but off" "GAMMA | ALPHA2 | BETA" "$(run_composer)"
eq "status sees 5 discovered" "4 enabled, 5 discovered" "$(bash "$SEGCTL" status)"

# ---------------------------------------------------------------------------
# Regression block: bugs caught in implementation review (cross-owner newest,
# missing-renderer no-downgrade, seed-no-frozen-order). Each uses its OWN cache
# + config so it can't perturb the assertions above.
# ---------------------------------------------------------------------------
mk_in() { # cache owner plugin version render order body
  local d="$1/$2/$3/$4"
  mkdir -p "$d/.claude-plugin" "$d/scripts"
  printf '%s' "$7" > "$d/scripts/seg.sh"
  if [ -n "$6" ]; then
    printf '{"name":"%s","render":"scripts/seg.sh","order":%s}\n' "$3" "$6" > "$d/.claude-plugin/statusline.json"
  else
    printf '{"name":"%s","render":"scripts/seg.sh"}\n' "$3" > "$d/.claude-plugin/statusline.json"
  fi
}

echo "== REGRESSION: cross-owner same-name -> newest version wins (owner-agnostic) =="
C2="$TMP/c2"; G2="$TMP/g2"
export CC_STATUS_CACHE="$C2" CC_STATUS_CONFIG="$G2"
# Same plugin "dup" under a lexically-LATER owner holding the OLDER version, and a
# lexically-EARLIER owner holding the NEWER version. Path sort would pick the wrong
# one; version sort must pick NEW.
mk_in "$C2" aaa dup 0.9.0 seg.sh 10 'printf NEW'
mk_in "$C2" zzz dup 0.1.0 seg.sh 10 'printf OLD'
printf 'dup=1:10\n' > "$G2"
eq "newest version wins across owners" "NEW" "$(printf '%s' "$SESSION" | bash "$COMPOSER")"

echo "== REGRESSION: missing renderer on newest -> skip segment, no downgrade =="
C3="$TMP/c3"; G3="$TMP/g3"
export CC_STATUS_CACHE="$C3" CC_STATUS_CONFIG="$G3"
# newest (0.9.0) points at a missing renderer; older (0.1.0) works. Must render
# NOTHING for this segment, never silently fall back to OLDER (which would lie).
mkdir -p "$C3/betmoar/m/0.9.0/.claude-plugin"
printf '{"name":"m","render":"scripts/GONE.sh","order":10}\n' > "$C3/betmoar/m/0.9.0/.claude-plugin/statusline.json"
mk_in "$C3" betmoar m 0.1.0 seg.sh 10 'printf OLDER'
printf 'm=1:10\n' > "$G3"
eq "missing newest renderer -> empty, no downgrade" "" "$(printf '%s' "$SESSION" | bash "$COMPOSER")"

echo "== REGRESSION: seed writes no frozen order; later manifest bump is honored =="
C4="$TMP/c4"; G4="$TMP/g4"
export CC_STATUS_CACHE="$C4" CC_STATUS_CONFIG="$G4"
mk_in "$C4" betmoar s 1.0.0 seg.sh "" 'printf S'   # manifest declares NO order
bash "$SEGCTL" seed >/dev/null
eq "seed writes bare flag, no :order" "s=1" "$(grep '^s=' "$G4")"

# restore the primary cache/config for any later assertions
export CC_STATUS_CACHE="$CACHE" CC_STATUS_CONFIG="$CONFIG"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
