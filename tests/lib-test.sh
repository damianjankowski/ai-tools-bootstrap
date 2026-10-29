#!/usr/bin/env bash
# Unit tests for lib/bootstrap-lib.sh. Commands are stubbed as shell functions,
# so nothing is installed. Run: make test
# Test functions are called indirectly through check().
# shellcheck disable=SC2329
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=lib/bootstrap-lib.sh
source lib/bootstrap-lib.sh

LOG="$(mktemp)"
fails=0

# Runs one test function in a subshell, so its stubs do not leak.
check() {
  local name="$1" fn="$2"
  : >"$LOG"
  if ( "$fn" ); then
    echo "ok   $name"
  else
    echo "FAIL $name"
    fails=$((fails + 1))
  fi
}

# ── tests ─────────────────────────────────────────────────────────────────────
t_lib_sources_strict() {
  bash -euo pipefail -c 'source lib/bootstrap-lib.sh'
}

check lib_sources_strict t_lib_sources_strict

rm -f "$LOG"
exit $((fails > 0))
