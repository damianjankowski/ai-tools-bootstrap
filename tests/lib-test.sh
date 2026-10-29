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

# Safety net: every command that installs or changes something fails unless a
# test stubs it, so a test can never reach the real tool.
for _c in brew npm npx curl claude bd codebase-memory-mcp dialog; do
  eval "${_c}() { echo \"UNSTUBBED ${_c} \$*\" >&2; return 99; }"
done
unset _c

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

# Loads the tool installer of each bootstrap-* script (they run bootstrap_main
# at the end, so they cannot be sourced whole).
load_installers() {
  local f
  for f in bootstrap-claude bootstrap-codex bootstrap-opencode; do
    eval "$(sed -n '/^_install_/,/^}/p' "$f")"
  done
}

# Stubs every tool check to "not installed".
not_installed() {
  _claude_installed()   { return 1; }
  _codex_installed()    { return 1; }
  _opencode_installed() { return 1; }
  _beads_installed()    { return 1; }
  _cbm_installed()      { return 1; }
}

# ── tests ─────────────────────────────────────────────────────────────────────
t_lib_sources_strict() {
  bash -euo pipefail -c 'source lib/bootstrap-lib.sh'
}

t_tool_install_failure() {
  load_installers; not_installed
  brew() { echo "brew $*" >>"$LOG"; return 1; }
  curl() { return 1; }
  local fn
  for fn in _install_beads _install_codebase_memory_mcp \
            _install_claude_code _install_codex _install_opencode; do
    if "$fn"; then echo "  $fn reported success" >&2; return 1; fi
  done
}

t_plugin_install_failure() {
  claude() { return 1; }
  _plugin_installed() { return 1; }
  _marketplace_exists() { return 0; }
  ! _install_plugin k@m src m
}

t_brew_args() {
  load_installers; not_installed
  brew() { echo "brew $*" >>"$LOG"; }
  _install_claude_code && _install_codex && _install_opencode && _install_beads || return 1
  [[ "$(cat "$LOG")" == "brew install --cask claude-code
brew install --cask codex
brew install opencode
brew install beads" ]]
}

t_installed_tool_skips_brew() {
  load_installers
  _claude_installed() { return 0; }
  brew() { echo "brew $*" >>"$LOG"; }
  _install_claude_code >/dev/null && [[ ! -s "$LOG" ]]
}

t_cbm_install_args() {
  local flag out
  flag="$(mktemp)"; rm -f "$flag"
  # not installed on the first check, installed after the install script ran
  _cbm_installed() { [[ -e "$flag" ]] || { touch "$flag"; return 1; }; }
  curl() { echo "curl $*" >>"$LOG"; echo 'echo "args=[$*]"'; }
  codebase-memory-mcp() { echo "cbm $*" >>"$LOG"; }
  out="$(_install_codebase_memory_mcp)" || return 1
  rm -f "$flag"
  [[ "$out" == *"args=[]"* ]] \
    && grep -q 'curl .*DeusData/codebase-memory-mcp/main/install.sh' "$LOG" \
    && ! grep -q 'cbm config set' "$LOG"
}

check lib_sources_strict t_lib_sources_strict
check tool_install_failure t_tool_install_failure
check plugin_install_failure t_plugin_install_failure
check brew_args t_brew_args
check installed_tool_skips_brew t_installed_tool_skips_brew
check cbm_install_args t_cbm_install_args

rm -f "$LOG"
exit $((fails > 0))
