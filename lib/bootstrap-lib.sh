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
SCRIPT_DIR="${_BOOTSTRAP_DIR:-}"
INSTALL_SH=""
INSTALL_TOOLS_SH=""
if [[ -n "$SCRIPT_DIR" ]]; then
  INSTALL_SH="${SCRIPT_DIR}/install.sh"
  INSTALL_TOOLS_SH="${SCRIPT_DIR}/install-tools.sh"
fi

INTERACTIVE=false
[[ -t 1 ]] && INTERACTIVE=true

# ── shared checks ─────────────────────────────────────────────────────────────
_cmd_exists()   { command -v "$1" &>/dev/null; }

_plugin_installed() {
  local key="$1"
  local f="$HOME/.claude/plugins/installed_plugins.json"
  _cmd_exists jq || return 1
  [[ -f "$f" ]] && jq -e --arg k "$key" '.plugins | has($k)' "$f" >/dev/null 2>&1
}

_plugin_version() {
  local key="$1"
  local f="$HOME/.claude/plugins/installed_plugins.json"
  _cmd_exists jq || { printf 'unknown'; return; }
  [[ -f "$f" ]] || { printf 'not installed'; return; }
  jq -r --arg k "$key" '.plugins[$k][0].version // "unknown"' "$f" 2>/dev/null || printf 'unknown'
}

_marketplace_exists() {
  local id="$1"
  local f="$HOME/.claude/plugins/known_marketplaces.json"
  _cmd_exists jq || return 1
  [[ -f "$f" ]] && jq -e --arg id "$id" 'has($id)' "$f" >/dev/null 2>&1
}

# check-skill-name is the name of one skill from the package (used as installed proxy).
# `npx skills ls` is slow (npm resolves the package on every run), so list once and
# reuse it; _install_skill clears the cache. --yes and </dev/null: when a newer
# `skills` release is not in the npx cache, npx asks "Ok to proceed?" — with stderr
# hidden that prompt is invisible and the script hangs before the picker opens.
_SKILLS_LS=""
_SKILLS_LS_LOADED=false
_skill_installed() {
  local skill_name="$1"
  _cmd_exists npx || return 1
  if [[ "$_SKILLS_LS_LOADED" != "true" ]]; then
    _SKILLS_LS="$(npx --yes skills ls -g --json </dev/null 2>/dev/null || true)"
    _SKILLS_LS_LOADED=true
  fi
  # skills >= 1.7 pretty-prints the JSON ("name": "x"), older releases did not
  grep -Eq "\"name\"[[:space:]]*:[[:space:]]*\"${skill_name}\"" <<< "$_SKILLS_LS"
}

# ── shared install helpers ────────────────────────────────────────────────────
_brew_install() {
  local formula="$1"
  if _cmd_exists brew; then
    brew install "$formula"
  else
    err "brew not found — install Homebrew first: https://brew.sh"; return 1
  fi
}

_npm_install() {
  local pkg="$1"
  _cmd_exists npm || { err "npm not found — install Node.js first: https://nodejs.org"; return 1; }
  npm install -g "$pkg"
}

_curl_install() {
  local url="$1"; shift
  curl -fsSL "$url" | bash -s -- "$@"
}

_install_skill() {
  local repo="$1" skills="${2:-}"
  _cmd_exists npx || { err "npx not found — install Node.js first: https://nodejs.org"; return 1; }
  local -a args=(--yes skills add "$repo" -g -y)
  local s
  for s in $skills; do args+=(--skill "$s"); done
  _SKILLS_LS_LOADED=false
  npx "${args[@]}"
}

# ── shared skill sets (last field of "skill|..." entries) ─────────────────────
# aws-samples/sample-apex-skills without its vendored copies (terraform-skill,
# skill-creator) and the skills that only maintain the APEX repo itself.
# Keep it on one logical line: entries are parsed with `read`, which stops at \n.
APEX_SKILLS="eks-best-practices eks-build eks-cost-intelligence eks-design eks-genai \
eks-ingress-migration eks-mcp-server eks-operation-review eks-platform-engineering \
eks-recon eks-security eks-upgrade-check eks-well-architected-review \
ecs-architect ecs-build ecs-devops ecs-genai ecs-modernize ecs-observability \
ecs-operation-review ecs-recon ecs-security dotnet-aws-ecs graviton-migration"

# google/skills (153 skills) narrowed to GKE + GCP operations. The rest of the
# catalog stays reachable through finding-google-skills.
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
MATTPOCOCK_SKILLS="handoff"

# ── shared tool checks + installs (common across all bootstrap-* scripts) ─────
_beads_installed() { _cmd_exists bd; }
_cbm_installed()   { _cmd_exists codebase-memory-mcp; }

_install_beads() {
  if _beads_installed; then ok "beads already present — skipping"; return 0; fi
  log "Installing beads..."
  if [[ -n "${INSTALL_TOOLS_SH:-}" ]] && [[ -f "$INSTALL_TOOLS_SH" ]]; then
    bash "$INSTALL_TOOLS_SH"
  elif _cmd_exists brew; then
    _brew_install beads
  else
    _curl_install https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh
  fi
  ok "beads installed"
}

_install_codebase_memory_mcp() {
  if _cbm_installed; then ok "codebase-memory-mcp already present — skipping"; return 0; fi
  log "Installing codebase-memory-mcp..."
  if [[ -n "${INSTALL_TOOLS_SH:-}" ]] && [[ -f "$INSTALL_TOOLS_SH" ]]; then
    bash "$INSTALL_TOOLS_SH" --with-mcp
  else
    _curl_install https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh --ui
    _cmd_exists codebase-memory-mcp || { err "codebase-memory-mcp install failed"; return 1; }
    codebase-memory-mcp config set auto_index true
  fi
  ok "codebase-memory-mcp installed"
}

_install_plugin() {
  local key="$1" mkt_src="$2" mkt_id="${3:-}"
  if _plugin_installed "$key"; then
    ok "${key%%@*} already installed — skipping"; return 0
  fi
  if [[ -n "$mkt_id" ]] && ! _marketplace_exists "$mkt_id"; then
    log "Registering marketplace $mkt_id..."
    claude plugin marketplace add "$mkt_src" || warn "marketplace add failed (may already exist)"
  fi
  log "Installing ${key%%@*}..."
  claude plugin install "$key"
  ok "${key%%@*} installed"
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
  claude plugin update "$key" || return 1
  after="$(_plugin_version "$key")"
  if [[ "$before" == "$after" ]]; then
    ok "${key%%@*} already up to date (${after})"
  else
    ok "${key%%@*} updated: ${before} → ${after}"
  fi
}

# Lists every plugin defined in COMPONENTS with its installed version.
bootstrap_list_plugin_versions() {
  local comp
  for comp in "${COMPONENTS[@]}"; do
    [[ "${comp%%|*}" == "plugin" ]] || continue
    local rest="${comp#*|}"
    local label key mkt_src mkt_id
    IFS='|' read -r label key mkt_src mkt_id <<< "$rest"
    if _plugin_installed "$key"; then
      printf '%-40s %s\n' "$label" "$(_plugin_version "$key")"
    else
      printf '%-40s %s\n' "$label" "not installed"
    fi
  done
}

# Updates every marketplace referenced by COMPONENTS once, then updates each
# installed plugin. Reads the global COMPONENTS array.
bootstrap_update_plugins() {
  _cmd_exists claude || { err "claude CLI not found — install Claude Code first"; return 1; }

  local -a mkt_ids=()
  local comp
  for comp in "${COMPONENTS[@]}"; do
    [[ "${comp%%|*}" == "plugin" ]] || continue
    local rest="${comp#*|}"
    local label key mkt_src mkt_id
    IFS='|' read -r label key mkt_src mkt_id <<< "$rest"
    [[ -n "$mkt_id" ]] || continue
    local seen=false m
    for m in "${mkt_ids[@]:-}"; do [[ "$m" == "$mkt_id" ]] && seen=true && break; done
    "$seen" || mkt_ids+=("$mkt_id")
  done

  if [[ "${#mkt_ids[@]}" -gt 0 ]]; then
    log "Updating plugin marketplaces..."
    claude plugin marketplace update || warn "marketplace update failed"
  fi

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

  printf '\n─────────────────────────────────────────\n'
  printf 'Plugin update summary:\n\n'
  for r in "${results[@]}"; do
    local lbl="${r%%:*}" st="${r##*:}"
    case "$st" in
      ok)   ok  "$lbl" ;;
      fail) err "$lbl — check output above for details" ;;
    esac
  done
  printf '\n'

  for r in "${results[@]}"; do
    [[ "${r##*:}" == "fail" ]] && return 1
  done
  return 0
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
      local label _ check_name
      IFS='|' read -r label _ check_name _ <<< "$rest"
      _skill_installed "$check_name"
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
  local -a dialog_args=()
  local -a item_labels=()
  local -a item_is_tool=()
  local n=0 h=0

  for comp in "${COMPONENTS[@]}"; do
    local type="${comp%%|*}"
    local rest="${comp#*|}"
    if [[ "$type" == "header" ]]; then
      h=$((h+1))
      dialog_args+=("h${h}" "${rest%%|*}" "off")
    else
      n=$((n+1))
      local label="${rest%%|*}"
      local status display_label
      if _comp_is_installed "$comp"; then
        status="off"
        display_label="${label} ✓"
      else
        status="on"
        display_label="$label"
      fi
      dialog_args+=("$n" "$display_label" "$status")
      item_labels[$n]="$display_label"
      [[ "$type" == "tool" ]] && item_is_tool[$n]=1 || item_is_tool[$n]=0
    fi
  done

  local list_h=$((n + h))
  local box_h=$((list_h + 7))
  [[ $box_h -gt 40 ]] && box_h=40

  if _cmd_exists dialog; then
    local raw result="" desc
    raw="$(dialog --stdout --no-tags --separate-output \
      --checklist "Select components to install:" \
      $box_h 65 $list_h \
      "${dialog_args[@]}")" || return 1
    while IFS= read -r desc; do
      [[ -z "$desc" ]] && continue
      if [[ "$desc" =~ ^[0-9]+$ ]] && [[ -n "${item_labels[$desc]:-}" ]]; then
        result+="$desc "; continue
      fi
      local i
      for i in "${!item_labels[@]}"; do
        if [[ "${item_labels[$i]}" == "$desc" ]]; then
          result+="$i "; break
        fi
      done
    done <<< "$raw"
    if [[ -n "${raw//[[:space:]]/}" ]] && [[ -z "${result// /}" ]]; then
      err "Could not map dialog output to components: ${raw//$'\n'/ }"
      return 1
    fi
    printf '%s' "${result% }"
  else
    _pick_components_text "$n" "${item_labels[@]}"
  fi
}

_pick_components_text() {
  local total="$1"; shift
  local -a labels=("" "$@")  # 1-indexed

  local n=0 h=0
  {
    printf '\n'
    for comp in "${COMPONENTS[@]}"; do
      local type="${comp%%|*}"
      local rest="${comp#*|}"
      if [[ "$type" == "header" ]]; then
        printf '%s\n\n' "${rest%%|*}"
      else
        n=$((n+1))
        local mark
        _comp_is_installed "$comp" && mark="✓" || mark=" "
        printf '  [%2d] %s  %s\n' "$n" "$mark" "${rest%%|*}"
      fi
    done
    printf '\nEnter numbers [1-%d] or Enter for all: ' "$total"
  } >/dev/tty

  local user_input
  read -r user_input < /dev/tty || user_input=""
  _parse_selection "$total" "${user_input:-}"
}

# Returns space-separated valid sorted numbers. Empty/invalid → all.
_parse_selection() {
  local max="$1" input="$2"
  local all
  all="$(seq 1 "$max" | tr '\n' ' ' | sed 's/ $//')"
  if [[ -z "${input// /}" ]]; then printf '%s' "$all"; return; fi
  local filtered
  filtered="$(printf '%s' "$input" | tr -s '[:space:]' '\n' \
    | awk -v m="$max" '$1~/^[0-9]+$/ && $1>=1 && $1<=m' || true)"
  if [[ -z "$filtered" ]]; then printf '%s' "$all"; return; fi
  printf '%s' "$filtered" | sort -nu | tr '\n' ' ' | sed 's/ $//'
}

# ── main runner ───────────────────────────────────────────────────────────────
# Reads COMPONENTS, picks selection, runs installs, prints summary.
bootstrap_run() {
  # Build item map: number → component string; track tool indices for non-interactive
  local -a item_map=("") # 1-indexed
  local auto_str=""
  local n=0
  for comp in "${COMPONENTS[@]}"; do
    local type="${comp%%|*}"
    [[ "$type" == "header" ]] && continue
    n=$((n+1))
    item_map[$n]="$comp"
    [[ "$type" == "tool" ]] && auto_str+="$n "
  done
  local total=$n

  local selected_str
  local -a selected

  if [[ "$INTERACTIVE" == "true" ]]; then
    local sel
    sel="$(_pick_components)" || { warn "Bootstrap cancelled."; return 0; }
    if [[ -z "${sel// /}" ]]; then warn "No components selected — nothing to do."; return 0; fi
    selected_str="$sel"
  else
    warn "Non-interactive mode — installing tools automatically."
    warn "Run interactively for plugins and configuration steps."
    selected_str="${auto_str% }"
    [[ -z "$selected_str" ]] && { warn "No tools defined — nothing to do."; return 0; }
  fi

  read -ra selected <<< "$selected_str"

  local -a results=()
  local status

  for num in "${selected[@]}"; do
    local comp="${item_map[$num]:-}"
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
      if _skill_installed "$check_name"; then
        ok "${label} already installed — skipping"
      else
        log "Installing ${label}..."
        _install_skill "$repo" "$skills" || status="fail"
      fi
    fi

    results+=("$(_comp_label "$comp"):${status}")
  done

  printf '\n─────────────────────────────────────────\n'
  printf 'Bootstrap summary:\n\n'
  for r in "${results[@]}"; do
    local lbl="${r%%:*}" st="${r##*:}"
    case "$st" in
      ok)   ok  "$lbl" ;;
      fail) err "$lbl — check output above for details" ;;
    esac
  done
  printf '\n'

  for r in "${results[@]}"; do
    [[ "${r##*:}" == "fail" ]] && return 1
  done
  return 0
}
