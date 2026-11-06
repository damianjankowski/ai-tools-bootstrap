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
  _openspec_installed() { return 1; }
  _cbm_installed()      { return 1; }
  _gsd_codex_installed()    { return 1; }
  _gsd_opencode_installed() { return 1; }
}

# ── tests ─────────────────────────────────────────────────────────────────────
t_lib_sources_strict() {
  bash -euo pipefail -c 'source lib/bootstrap-lib.sh'
}

t_tool_install_failure() {
  load_installers; not_installed
  brew() { echo "brew $*" >>"$LOG"; return 1; }
  curl() { return 1; }
  npx() { return 1; }
  local fn
  for fn in _install_gsd_core_codex _install_gsd_core_opencode _install_beads _install_openspec _install_codebase_memory_mcp \
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
  _install_claude_code && _install_codex && _install_opencode && _install_beads && _install_openspec || return 1
  [[ "$(cat "$LOG")" == "brew install --cask claude-code
brew install --cask codex
brew install opencode
brew install beads
brew install openspec" ]]
}

t_gsd_core_args() {
  load_installers; not_installed
  npx() { echo "npx $*" >>"$LOG"; }
  _install_gsd_core_codex && _install_gsd_core_opencode || return 1
  [[ "$(cat "$LOG")" == "npx --yes @opengsd/gsd-core@latest --codex --global
npx --yes @opengsd/gsd-core@latest --opencode --global" ]]
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

t_parse_selection() {
  [[ "$(_parse_selection 10 "3 1,2  3")" == "1 2 3" ]] || return 1
  [[ "$(_parse_selection 10 "1,,10")" == "1 10" ]] || return 1
  local bad out
  for bad in "1-3" "q" "0" "11" "a"; do
    if out="$(_parse_selection 10 "$bad")" || [[ -n "$out" ]]; then
      echo "  accepted: $bad" >&2; return 1
    fi
  done
}

t_text_picker_eof() {
  ! _pick_components_text 3 "1 2" "  [ 1]    a" </dev/null 2>/dev/null
}

t_text_picker_input() {
  local out errf
  errf="$(mktemp)"
  out="$(_pick_components_text 3 "1 2" "x" <<< $'x\n2,1' 2>"$errf")" || return 1
  [[ "$out" == "1 2" ]] && grep -q 'Invalid selection: x' "$errf" || return 1
  rm -f "$errf"
  [[ "$(_pick_components_text 3 "1 2" "x" <<< '' 2>/dev/null)" == "1 2" ]] || return 1
  ! _pick_components_text 3 "1 2" "x" <<< 'q' >/dev/null 2>&1
}

t_main_no_tty() {
  local errf rc=0
  errf="$(mktemp)"
  bootstrap_run() { echo "run $*" >>"$LOG"; }
  bootstrap_main </dev/null 2>"$errf" || rc=$?
  [[ $rc -eq 1 ]] && grep -q -- '--yes' "$errf" && [[ ! -s "$LOG" ]]
}

t_main_yes() {
  bootstrap_run() { echo "run $*"; }
  [[ "$(bootstrap_main --yes </dev/null)" == "run --yes" ]]
}

t_main_unknown() {
  local errf rc=0
  errf="$(mktemp)"
  bootstrap_run() { echo "run $*" >>"$LOG"; }
  bootstrap_main --updte >/dev/null 2>"$errf" || rc=$?
  [[ $rc -eq 2 ]] && grep -q 'Unknown option: --updte' "$errf" \
    && grep -q 'Usage:' "$errf" && [[ ! -s "$LOG" ]]
}

t_main_extra_args() {
  local rc=0
  bootstrap_run() { echo "run $*" >>"$LOG"; }
  bootstrap_main --yes --update >/dev/null 2>&1 || rc=$?
  [[ $rc -eq 2 && ! -s "$LOG" ]]
}

t_main_help() {
  local out
  out="$(bootstrap_main -h)" && [[ "$out" == *--yes* ]]
}

t_run_yes_tools_only() {
  COMPONENTS=("header|H" "tool|T|t_chk|t_inst" "plugin|P|p@m|src|m")
  t_chk() { return 1; }
  t_inst() { echo inst >>"$LOG"; }
  _install_plugin() { echo plugin >>"$LOG"; }
  bootstrap_run --yes >/dev/null 2>&1 && [[ "$(cat "$LOG")" == "inst" ]]
}

t_summary_fail() {
  set -u
  ! _print_summary S "a:ok" "b:fail" >/dev/null 2>&1 && _print_summary S >/dev/null
}

t_plugin_scope() {
  HOME="$(mktemp -d)"
  mkdir -p "$HOME/.claude/plugins"
  echo '{"plugins":{"a@m":[{"scope":"local","version":"1"}],"b@m":[{"scope":"local","version":"1"},{"scope":"user","version":"2"}]}}' \
    >"$HOME/.claude/plugins/installed_plugins.json"
  ! _plugin_installed a@m && _plugin_installed b@m && [[ "$(_plugin_version b@m)" == "2" ]]
}

t_jq_preflight() {
  HOME="$(mktemp -d)"
  COMPONENTS=("plugin|P|p@m|src|m")
  _cmd_exists() { [[ "$1" != jq ]] && command -v "$1" >/dev/null; }
  claude() { :; }
  local errf
  errf="$(mktemp)"
  ! bootstrap_update_plugins >/dev/null 2>"$errf" && grep -q 'jq not found' "$errf" || return 1
  : >"$errf"
  ! bootstrap_list_plugin_versions >/dev/null 2>"$errf" && grep -q 'jq not found' "$errf"
}

t_marketplace_update_per_id() {
  COMPONENTS=("plugin|A|a@m1|s1|m1" "plugin|B|b@m2|s2|m2" "plugin|C|c@m1|s1|m1")
  claude() { echo "$*" >>"$LOG"; }
  _update_plugin() { :; }
  bootstrap_update_plugins >/dev/null 2>&1 || return 1
  [[ "$(grep 'marketplace' "$LOG")" == "plugin marketplace update m1
plugin marketplace update m2" ]]
}

t_skill_bundle() {
  _SKILLS_LS_LOADED=true
  _SKILLS_LS='[{"name": "handoff"}]'
  _skill_bundle_installed handoff "handoff" \
    && ! _skill_bundle_installed handoff "handoff grill-me" \
    && _skill_bundle_installed handoff ""
}

check lib_sources_strict t_lib_sources_strict
check tool_install_failure t_tool_install_failure
check plugin_install_failure t_plugin_install_failure
check brew_args t_brew_args
check installed_tool_skips_brew t_installed_tool_skips_brew
check cbm_install_args t_cbm_install_args
check parse_selection t_parse_selection
check text_picker_eof t_text_picker_eof
check text_picker_input t_text_picker_input
check main_no_tty t_main_no_tty
check main_yes t_main_yes
check main_unknown t_main_unknown
check main_help t_main_help
check main_extra_args t_main_extra_args
check run_yes_tools_only t_run_yes_tools_only
check summary_fail t_summary_fail
check plugin_scope t_plugin_scope
check jq_preflight t_jq_preflight
check marketplace_update_per_id t_marketplace_update_per_id
check skill_bundle t_skill_bundle

rm -f "$LOG"
exit $((fails > 0))
