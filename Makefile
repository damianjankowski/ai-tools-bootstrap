.PHONY: help \
        bootstrap bootstrap-codex bootstrap-opencode \
        skills-update plugins-update plugins-list \
        install-beads install-openspec install-codebase-memory-mcp \
        cbm-ui cbm-auto-index cbm-update \
        init-beads setup-claude setup-codex setup-list \
        bd-prime bd-ready bd-backup _bd-check \
        lint test

# ── help ──────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "AI tools bootstrap"
	@echo "─────────────────────────────────────────────"
	@echo "  bootstrap                  Claude Code — interactive install (dialog TUI)"
	@echo "  bootstrap-codex            Codex — interactive install (dialog TUI)"
	@echo "  bootstrap-opencode         OpenCode — interactive install (dialog TUI)"
	@echo "  skills-update              Update Agent Skills (npx skills) — Codex/OpenCode"
	@echo "  plugins-update             Update Claude Code plugins (claude plugin update)"
	@echo "  plugins-list               Show installed Claude Code plugin versions"
	@echo ""
	@echo "Install"
	@echo "  install-beads              Install beads"
	@echo "  install-openspec           Install openspec"
	@echo "  install-codebase-memory-mcp  Install codebase-memory-mcp"
	@echo ""
	@echo "codebase-memory-mcp"
	@echo "  cbm-ui                     Start Graph Visualization UI (port 9749)"
	@echo "  cbm-auto-index             Enable auto-indexing on session start"
	@echo "  cbm-update                 Update codebase-memory-mcp to latest"
	@echo ""
	@echo "beads"
	@echo "  init-beads                 bd init — initialize in current project"
	@echo "  setup-claude               bd setup claude"
	@echo "  setup-codex                bd setup codex"
	@echo "  setup-list                 bd setup --list"
	@echo "  bd-prime                   bd prime — print workflow context + memories"
	@echo "  bd-ready                   bd ready — list tasks with no open blockers"
	@echo "  bd-backup                  bd backup sync"
	@echo ""
	@echo "Development"
	@echo "  lint                       bash -n + shellcheck on all scripts"
	@echo "  test                       Run lib unit tests (stubbed, installs nothing)"
	@echo ""

# Runs one lib function: $(LIB) <function> [args]
LIB = bash -euo pipefail -c 'source lib/bootstrap-lib.sh && "$$@"' _

# ── bootstrap ─────────────────────────────────────────────────────────────────
bootstrap:
	@bash ./bootstrap-claude

bootstrap-codex:
	@bash ./bootstrap-codex

bootstrap-opencode:
	@bash ./bootstrap-opencode

skills-update:
	@$(LIB) _skills update -g -y

plugins-update:
	@bash ./bootstrap-claude --update

plugins-list:
	@bash ./bootstrap-claude --list-versions

# ── install ───────────────────────────────────────────────────────────────────
install-beads:
	@$(LIB) _install_beads

install-openspec:
	@$(LIB) _install_openspec

install-codebase-memory-mcp:
	@$(LIB) _install_codebase_memory_mcp

# ── codebase-memory-mcp ───────────────────────────────────────────────────────
cbm-ui:
	@command -v codebase-memory-mcp >/dev/null || { echo "codebase-memory-mcp not installed. Run: make install-codebase-memory-mcp"; exit 1; }
	@codebase-memory-mcp --ui=true --port=9749

cbm-auto-index:
	@command -v codebase-memory-mcp >/dev/null || { echo "codebase-memory-mcp not installed. Run: make install-codebase-memory-mcp"; exit 1; }
	@codebase-memory-mcp config set auto_index true
	@echo "✓ Auto-index enabled (new projects indexed on first connection)"

cbm-update:
	@command -v codebase-memory-mcp >/dev/null || { echo "codebase-memory-mcp not installed. Run: make install-codebase-memory-mcp"; exit 1; }
	@codebase-memory-mcp update

# ── beads ─────────────────────────────────────────────────────────────────────
_bd-check:
	@command -v bd >/dev/null || { echo "beads not installed. Run: make install-beads"; exit 1; }

init-beads: _bd-check
	@echo "▶ Initializing beads in current project..."
	@bd init
	@echo "✓ Beads initialized — run 'make setup-claude' next"

setup-claude: _bd-check
	@echo "▶ Setting up beads for Claude Code..."
	@bd setup claude
	@echo "✓ Done"

setup-codex: _bd-check
	@echo "▶ Setting up beads for Codex CLI..."
	@bd setup codex
	@echo "✓ Done"

setup-list: _bd-check
	@bd setup --list

bd-prime: _bd-check
	@bd prime

bd-ready: _bd-check
	@bd ready

bd-backup: _bd-check
	@bd backup sync

# ── development ───────────────────────────────────────────────────────────────
SCRIPTS = bootstrap-claude bootstrap-codex bootstrap-opencode lib/bootstrap-lib.sh tests/lib-test.sh

lint:
	@for f in $(SCRIPTS); do bash -n "$$f" || exit 1; done
	@shellcheck -x $(SCRIPTS)

test:
	@bash tests/lib-test.sh
