#!/usr/bin/env bash
# bootstrap-lib.sh — source this, do not execute directly.
#
# Callers must set _BOOTSTRAP_DIR before sourcing:
#   _BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
#   source "${_BOOTSTRAP_DIR}/lib/bootstrap-lib.sh"
#
# Callers must define a COMPONENTS array. Each element is pipe-delimited:
#
#   "header|── Section Label ──────────────────────"
#   "tool|Display Label|check_fn|install_fn"
#   "plugin|Display Label|plugin@marketplace|marketplace-source|marketplace-id"
#   "skill|Display Label|org/repo|check-skill-name[|skill-a skill-b ...]"
#         ↑ Agent Skills format (npx skills add -g), works on Codex/Cursor/Copilot/etc.
#           Optional last field: install only these skills (space-separated names).
#
# After defining COMPONENTS (and any custom install_* functions), call:
#   bootstrap_run

# ── helpers ───────────────────────────────────────────────────────────────────
log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

# ── environment ───────────────────────────────────────────────────────────────
# @latest: a bare `npx skills` keeps reusing whatever version is in the npx cache.
SKILLS_PKG="skills@latest"

# ── shared checks ─────────────────────────────────────────────────────────────
_cmd_exists()   { command -v "$1" &>/dev/null; }

# Fails with a hint when a required command is missing.
_need() {
  _cmd_exists "$1" || { err "$1 not found — ${2:-brew install $1}"; return 1; }
}

# Plugin commands need the claude CLI, and jq to read its JSON state.
_need_plugin_tools() {
  _need claude "install Claude Code first (make bootstrap)" && _need jq
}

# Only user-scope installs count; project/local scopes belong to other repos.
_plugin_installed() {
  local key="$1"
  local f="$HOME/.claude/plugins/installed_plugins.json"
  _cmd_exists jq || return 1
  [[ -f "$f" ]] && jq -e --arg k "$key" 'any(.plugins[$k][]?; .scope == "user")' "$f" >/dev/null 2>&1
}

_plugin_version() {
  local key="$1"
  local f="$HOME/.claude/plugins/installed_plugins.json"
  _cmd_exists jq || { printf 'unknown'; return; }
  [[ -f "$f" ]] || { printf 'not installed'; return; }
  jq -r --arg k "$key" 'first(.plugins[$k][]? | select(.scope == "user") | .version) // "unknown"' "$f" 2>/dev/null \
    || printf 'unknown'
}

_marketplace_exists() {
  local id="$1"
  local f="$HOME/.claude/plugins/known_marketplaces.json"
  _cmd_exists jq || return 1
  [[ -f "$f" ]] && jq -e --arg id "$id" 'has($id)' "$f" >/dev/null 2>&1
}

# ── settings.json owned by chezmoi ────────────────────────────────────────────
# Where chezmoi manages ~/.claude/settings.json, chezmoi decides which plugins
# are on (enabledPlugins). The bootstrap only downloads plugins and registers
# marketplaces. `claude plugin install` and `marketplace add` still write
# settings.json, so _keep_settings puts the file back as it was. Where chezmoi
# does not manage the file (for example a Mac that skips ~/.claude), the claude
# CLI turns plugins on as usual.
_settings_file() { printf '%s/.claude/settings.json' "$HOME"; }

_settings_managed() {
  _cmd_exists chezmoi && chezmoi source-path "$(_settings_file)" >/dev/null 2>&1
}

# Runs "$@" and restores settings.json if chezmoi manages it. Keeps the exit code.
_keep_settings() {
  local f backup rc=0
  f="$(_settings_file)"
  if [[ ! -f "$f" ]] || ! _settings_managed; then
    "$@"
    return
  fi
  backup="$(mktemp)" || return 1
  cp -p "$f" "$backup" || { rm -f "$backup"; return 1; }
  "$@" || rc=$?
  if ! cmp -s "$backup" "$f"; then
    cp -p "$backup" "$f" && log "settings.json restored: chezmoi decides which plugins are on"
  fi
  rm -f "$backup"
  return "$rc"
}

_plugin_enabled() {
  jq -e --arg k "$1" '.enabledPlugins[$k] == true' "$(_settings_file)" >/dev/null 2>&1
}

# Warns when chezmoi manages settings.json and does not turn the plugin on.
_warn_if_off() {
  local key="$1"
  _settings_managed || return 0
  _plugin_enabled "$key" && return 0
  warn "${key%%@*} is installed but off: add \"${key}\": true to enabledPlugins in the chezmoi source of ~/.claude/settings.json, then run chezmoi apply"
}

# check-skill-name is the name of one skill from the package (used as installed proxy).
# `npx skills ls` is slow (npm resolves the package on every run), so list once and
# reuse it; _install_skill clears the cache. </dev/null: if npx still asks anything,
# the prompt is invisible with stderr hidden and the script would hang before the
# picker opens.
_SKILLS_LS=""
_SKILLS_LS_LOADED=false
_skill_installed() {
  local skill_name="$1"
  _cmd_exists npx || return 1
  if [[ "$_SKILLS_LS_LOADED" != "true" ]]; then
    _SKILLS_LS="$(_skills ls -g --json </dev/null 2>/dev/null || true)"
    _SKILLS_LS_LOADED=true
  fi
  # skills >= 1.7 pretty-prints the JSON ("name": "x"), older releases did not
  grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${skill_name}\"" <<< "$_SKILLS_LS"
}

# A bundle counts as installed only when every listed skill is (so skills
# added to a list later still get installed). No list: check_name alone.
_skill_bundle_installed() {
  local check_name="$1" skills="${2:-}" s
  for s in ${skills:-$check_name}; do
    _skill_installed "$s" || return 1
  done
}

# ── shared install helpers ────────────────────────────────────────────────────
_brew_install() {
  _need brew "install Homebrew first: https://brew.sh" || return 1
  brew install "$@"
}

# Runs the skills CLI (Agent Skills, https://skills.sh).
_skills() {
  _need npx "install Node.js first: https://nodejs.org" || return 1
  npx --yes "$SKILLS_PKG" "$@"
}

_install_skill() {
  local repo="$1" skills="${2:-}"
  local -a args=(add "$repo" -g -y)
  local s
  for s in $skills; do args+=(--skill "$s"); done
  _SKILLS_LS_LOADED=false
  _skills "${args[@]}"
}

# ── shared skill sets (last field of "skill|..." entries) ─────────────────────
# aws-samples/sample-apex-skills without its vendored copies (terraform-skill,
# skill-creator) and the skills that only maintain the APEX repo itself.
# Keep it on one logical line: entries are parsed with `read`, which stops at \n.
# shellcheck disable=SC2034  # used in COMPONENTS of bootstrap-*
APEX_SKILLS="eks-best-practices eks-build eks-cost-intelligence eks-design eks-genai \
eks-ingress-migration eks-mcp-server eks-operation-review eks-platform-engineering \
eks-recon eks-security eks-upgrade-check eks-well-architected-review \
ecs-architect ecs-build ecs-devops ecs-genai ecs-modernize ecs-observability \
ecs-operation-review ecs-recon ecs-security dotnet-aws-ecs graviton-migration"

# google/skills (153 skills) narrowed to GKE + GCP operations. The rest of the
# catalog stays reachable through finding-google-skills.
# shellcheck disable=SC2034  # used in COMPONENTS of bootstrap-*
GOOGLE_SKILLS="gcloud google-cloud-recipe-auth finding-google-skills \
gke-basics gke-cluster-creation gke-golden-path gke-productionize gke-reliability \
gke-upgrades gke-networking gke-service-networking gke-storage gke-storage-troubleshooting \
gke-cluster-autoscaler gke-compute-classes gke-workload-scaling \
gke-workload-scaling-troubleshooting gke-workload-troubleshooting gke-node-notready \
gke-workload-identity gke-workload-security gke-platform-security gke-multitenancy \
gke-backup-dr gke-observability gke-alert-configuration gke-cost-analysis \
gke-cost-optimization gke-manifest-generation gke-app-onboarding \
cloud-logging-query-generation cloud-logging-configuration-basics \
cloud-logging-cross-project-configuration cloud-monitoring-promql-query \
cloud-monitoring-metric-selection cloud-trace-querying google-cloud-slo-alert-configuration \
google-cloud-networking-observability google-cloud-global-frontend-configuration \
iam-helper-for-policy-management iam-helper-for-policy-simulator \
iam-helper-for-privileged-access-management iam-helper-for-troubleshooting \
google-cloud-waf-reliability google-cloud-waf-security google-cloud-waf-cost-optimization \
google-cloud-waf-operational-excellence google-cloud-waf-performance-optimization \
google-cloud-waf-sustainability"

# mattpocock/skills, picked one by one: without a list skills.sh also installs
# the in-progress/ and misc/ buckets. grill-me and grill-with-docs only delegate
# to grilling (and domain-modeling), so add those dependencies with them.
# shellcheck disable=SC2034  # used in COMPONENTS of bootstrap-*
MATTPOCOCK_SKILLS="handoff"

# ── shared tool checks + installs (common across all bootstrap-* scripts) ─────
_beads_installed() { _cmd_exists bd; }
_cbm_installed()   { _cmd_exists codebase-memory-mcp; }

_install_beads() {
  if _beads_installed; then ok "beads already present — skipping"; return 0; fi
  log "Installing beads..."
  _brew_install beads || return 1
  ok "beads installed"
}

_install_codebase_memory_mcp() {
  if _cbm_installed; then ok "codebase-memory-mcp already present — skipping"; return 0; fi
  log "Installing codebase-memory-mcp..."
  # No brew formula. Installs the latest release to ~/.local/bin and registers
  # the MCP server in the agents it detects. Needs pipefail (all callers set it).
  curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh \
    | bash -s || return 1
  _cbm_installed || { err "codebase-memory-mcp install failed"; return 1; }
  ok "codebase-memory-mcp installed"
}

_install_plugin() {
  local key="$1" mkt_src="$2" mkt_id="${3:-}"
  _need_plugin_tools || return 1
  if _plugin_installed "$key"; then
    ok "${key%%@*} already installed — skipping"
    _warn_if_off "$key"
    return 0
  fi
  if [[ -n "$mkt_id" ]] && ! _marketplace_exists "$mkt_id"; then
    log "Registering marketplace $mkt_id..."
    _keep_settings claude plugin marketplace add "$mkt_src" \
      || warn "marketplace add failed (may already exist)"
  fi
  log "Installing ${key%%@*}..."
  _keep_settings claude plugin install "$key" || return 1
  ok "${key%%@*} installed"
  _warn_if_off "$key"
}

# ── plugin updates (claude CLI uses its own update path, not `npx skills`) ────
_update_plugin() {
  local key="$1"
  if ! _plugin_installed "$key"; then
    warn "${key%%@*} not installed — skipping"; return 0
  fi
  local before after
  before="$(_plugin_version "$key")"
  log "Updating ${key%%@*} (${before})..."
  _keep_settings claude plugin update "$key" || return 1
  after="$(_plugin_version "$key")"
  if [[ "$before" == "$after" ]]; then
    ok "${key%%@*} already up to date (${after})"
  else
    ok "${key%%@*} updated: ${before} → ${after}"
  fi
}

# Lists every plugin defined in COMPONENTS with its installed version.
bootstrap_list_plugin_versions() {
  _need_plugin_tools || return 1
  local comp managed=no
  _settings_managed && managed=yes
  for comp in "${COMPONENTS[@]}"; do
    [[ "${comp%%|*}" == "plugin" ]] || continue
    local rest="${comp#*|}"
    local label key mkt_src mkt_id
    IFS='|' read -r label key mkt_src mkt_id <<< "$rest"
    if _plugin_installed "$key"; then
      local off=""
      [[ "$managed" == yes ]] && ! _plugin_enabled "$key" && off=" (off: not in chezmoi enabledPlugins)"
      printf '%-40s %s%s\n' "$label" "$(_plugin_version "$key")" "$off"
    else
      printf '%-40s %s\n' "$label" "not installed"
    fi
  done
}

# Updates every marketplace referenced by COMPONENTS once, then updates each
# installed plugin. Reads the global COMPONENTS array.
bootstrap_update_plugins() {
  _need_plugin_tools || return 1

  local -a mkt_ids=()
  local comp
  for comp in "${COMPONENTS[@]}"; do
    [[ "${comp%%|*}" == "plugin" ]] || continue
    local rest="${comp#*|}"
    local label key mkt_src mkt_id
    IFS='|' read -r label key mkt_src mkt_id <<< "$rest"
    [[ -n "$mkt_id" ]] || continue
    local seen=false m
    for m in "${mkt_ids[@]+"${mkt_ids[@]}"}"; do [[ "$m" == "$mkt_id" ]] && seen=true && break; done
    "$seen" || mkt_ids+=("$mkt_id")
  done

  local id
  for id in "${mkt_ids[@]+"${mkt_ids[@]}"}"; do
    log "Updating marketplace ${id}..."
    _keep_settings claude plugin marketplace update "$id" || warn "marketplace ${id} update failed"
  done

  local -a results=()
  local status
  for comp in "${COMPONENTS[@]}"; do
    [[ "${comp%%|*}" == "plugin" ]] || continue
    local rest="${comp#*|}"
    local label key mkt_src mkt_id
    IFS='|' read -r label key mkt_src mkt_id <<< "$rest"
    status="ok"
    _update_plugin "$key" || status="fail"
    results+=("${label}:${status}")
  done

  _print_summary "Plugin update summary" ${results[@]+"${results[@]}"}
}

# ── component helpers (parse COMPONENTS entries) ──────────────────────────────
# Returns: 0 if component is installed/configured, 1 otherwise
_comp_is_installed() {
  local comp="$1"
  local type="${comp%%|*}"
  local rest="${comp#*|}"
  case "$type" in
    tool)
      local label check_fn _
      IFS='|' read -r label check_fn _ <<< "$rest"
      [[ "$check_fn" == "-" ]] && return 1
      "$check_fn" 2>/dev/null
      ;;
    plugin)
      local label key _
      IFS='|' read -r label key _ <<< "$rest"
      _plugin_installed "$key"
      ;;
    skill)
      local label _ check_name skills
      IFS='|' read -r label _ check_name skills <<< "$rest"
      _skill_bundle_installed "$check_name" "$skills"
      ;;
    *) return 1 ;;
  esac
}

# Returns label of component
_comp_label() {
  local comp="$1"
  local rest="${comp#*|}"
  printf '%s' "${rest%%|*}"
}

# ── component picker ──────────────────────────────────────────────────────────
# Reads global COMPONENTS array. Prints space-separated numbers to stdout.
# Exits non-zero if user cancels.
_pick_components() {
  local -a dialog_args=() item_labels=() header_labels=() lines=()
  local defaults="" n=0 h=0 comp

  # One pass: each install check (slow for skills) runs once.
  for comp in "${COMPONENTS[@]}"; do
    local type="${comp%%|*}"
    local rest="${comp#*|}"
    local label="${rest%%|*}"
    if [[ "$type" == "header" ]]; then
      h=$((h+1))
      dialog_args+=("h${h}" "$label" "off")
      header_labels+=("$label")
      lines+=("" "$label")
    else
      n=$((n+1))
      if _comp_is_installed "$comp"; then
        dialog_args+=("$n" "${label} ✓" "off")
        item_labels[n]="${label} ✓"
        lines+=("$(printf '  [%2d] ✓  %s' "$n" "$label")")
      else
        dialog_args+=("$n" "$label" "on")
        item_labels[n]="$label"
        lines+=("$(printf '  [%2d]    %s' "$n" "$label")")
        defaults+="$n "
      fi
    fi
  done

  if ! _cmd_exists dialog; then
    _pick_components_text "$n" "${defaults% }" "${lines[@]}"
    return
  fi

  # dialog prints tags or labels (depends on version); headers are not items.
  local raw result="" desc i
  raw="$(dialog --stdout --no-tags --separate-output \
    --checklist "Select components to install:" 0 65 0 \
    "${dialog_args[@]}")" || return 1
  while IFS= read -r desc; do
    [[ -z "$desc" || "$desc" =~ ^h[0-9]+$ ]] && continue
    if [[ "$desc" =~ ^[0-9]+$ ]] && [[ -n "${item_labels[desc]:-}" ]]; then
      result+="$desc "; continue
    fi
    for i in "${!item_labels[@]}"; do
      [[ "${item_labels[i]}" == "$desc" ]] && { result+="$i "; continue 2; }
    done
    for i in "${header_labels[@]+"${header_labels[@]}"}"; do
      [[ "$i" == "$desc" ]] && continue 2
    done
    err "Could not map dialog output to a component: $desc"
    return 1
  done <<< "$raw"
  printf '%s' "${result% }"
}

# Text fallback without dialog. Prompts on stderr (stdout is the result).
_pick_components_text() {
  local max="$1" defaults="$2"; shift 2
  local input sel
  printf '%s\n' "$@" >&2
  while true; do
    printf '\nNumbers (e.g. 1 3 5 or 1,3,5), Enter = not yet installed, q = cancel: ' >&2
    read -r input || return 1
    [[ "$input" == "q" ]] && return 1
    [[ -z "${input// /}" ]] && { printf '%s' "$defaults"; return 0; }
    sel="$(_parse_selection "$max" "$input")" && { printf '%s' "$sel"; return 0; }
    err "Invalid selection: $input"
  done
}

# Prints valid numbers sorted and unique; returns 1 if any token is invalid.
_parse_selection() {
  local max="$1" input="$2" t
  local -a tokens=() nums=()
  IFS=', ' read -ra tokens <<< "$input"
  for t in "${tokens[@]+"${tokens[@]}"}"; do
    [[ -z "$t" ]] && continue
    [[ "$t" =~ ^[0-9]+$ ]] && (( 10#$t >= 1 && 10#$t <= max )) || return 1
    nums+=("$((10#$t))")
  done
  [[ ${#nums[@]} -gt 0 ]] || return 1
  printf '%s\n' "${nums[@]}" | sort -nu | tr '\n' ' ' | sed 's/ $//'
}

# ── main runner ───────────────────────────────────────────────────────────────
# Prints "<title>:" and one line per "label:status" entry.
# Returns 1 if any status is "fail".
_print_summary() {
  local title="$1"; shift
  local r rc=0
  printf '\n─────────────────────────────────────────\n'
  printf '%s:\n\n' "$title"
  for r in "$@"; do
    if [[ "${r##*:}" == "fail" ]]; then
      err "${r%:*} — check output above for details"; rc=1
    else
      ok "${r%:*}"
    fi
  done
  printf '\n'
  return "$rc"
}

bootstrap_usage() {
  printf 'Usage: %s [-y|--yes] [-h|--help]\n' "$(basename "$0")"
  printf '  -y, --yes        no prompt: install the tools only (no plugins or skills)\n'
  printf '  -h, --help       show this help\n'
  [[ -z "${BOOTSTRAP_EXTRA_USAGE:-}" ]] || printf '%s\n' "$BOOTSTRAP_EXTRA_USAGE"
}

# Entry point of every bootstrap-* script. Never installs without a choice:
# no terminal and no --yes means stop.
bootstrap_main() {
  if [[ $# -gt 1 ]]; then
    err "Too many options: $*"
    bootstrap_usage >&2
    return 2
  fi
  case "${1:-}" in
    -y|--yes)  bootstrap_run --yes ;;
    -h|--help) bootstrap_usage ;;
    "")
      if [[ -t 0 ]]; then
        bootstrap_run
      else
        err "No terminal — rerun with --yes to install tools only"
        return 1
      fi
      ;;
    *)
      err "Unknown option: $1"
      bootstrap_usage >&2
      return 2
      ;;
  esac
}

# Reads COMPONENTS, picks selection, runs installs, prints summary.
# --yes: no picker, install every tool item.
bootstrap_run() {
  local -a item_map=("") # 1-indexed: number → component string
  local tools="" n=0 comp num
  for comp in "${COMPONENTS[@]}"; do
    local type="${comp%%|*}"
    [[ "$type" == "header" ]] && continue
    n=$((n+1))
    item_map[n]="$comp"
    [[ "$type" == "tool" ]] && tools+="$n "
  done

  local sel
  local -a selected
  if [[ "${1:-}" == "--yes" ]]; then
    warn "--yes: installing tools only. Run without --yes to pick plugins and skills."
    sel="$tools"
  else
    sel="$(_pick_components)" || { warn "Bootstrap cancelled."; return 0; }
  fi
  if [[ -z "${sel// /}" ]]; then warn "No components selected — nothing to do."; return 0; fi

  read -ra selected <<< "$sel"

  local -a results=()
  local status

  for num in "${selected[@]}"; do
    comp="${item_map[num]:-}"
    [[ -z "$comp" ]] && continue
    local type="${comp%%|*}"
    local rest="${comp#*|}"
    status="ok"

    if [[ "$type" == "tool" ]]; then
      local label check_fn install_fn
      IFS='|' read -r label check_fn install_fn <<< "$rest"
      "$install_fn" || status="fail"
    elif [[ "$type" == "plugin" ]]; then
      local label key mkt_src mkt_id
      IFS='|' read -r label key mkt_src mkt_id <<< "$rest"
      _install_plugin "$key" "$mkt_src" "$mkt_id" || status="fail"
    elif [[ "$type" == "skill" ]]; then
      local label repo check_name skills
      IFS='|' read -r label repo check_name skills <<< "$rest"
      if _skill_bundle_installed "$check_name" "$skills"; then
        ok "${label} already installed — skipping"
      else
        log "Installing ${label}..."
        _install_skill "$repo" "$skills" || status="fail"
      fi
    fi

    results+=("$(_comp_label "$comp"):${status}")
  done

  _print_summary "Bootstrap summary" ${results[@]+"${results[@]}"}
}
