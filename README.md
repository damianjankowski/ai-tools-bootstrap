# ai-bootstrap

Interactive installer for AI coding tools, plugins, and skills.

## Requirements

- macOS with [Homebrew](https://brew.sh)
- `jq`, for Claude Code plugins: `brew install jq`
- Node.js with `npx`, for Agent Skills
- Claude Code CLI, for plugins (the bootstrap can install it)
- Optional: `brew install dialog` for a checklist UI. Without it, you get a text prompt.

## Usage

```bash
make bootstrap           # Claude Code
make bootstrap-codex     # Codex
make bootstrap-opencode  # OpenCode
make help                # all targets
```

You pick what to install. Items that are already installed are marked with ✓ and are skipped.

The scripts also take flags:

```bash
./bootstrap-claude --yes            # no prompt: install the tools only (no plugins or skills)
./bootstrap-claude --help           # all flags
./bootstrap-claude --update         # update installed plugins  (make plugins-update)
./bootstrap-claude --list-versions  # installed plugin versions (make plugins-list)
```

Without a terminal (for example in CI), the scripts stop unless you pass `--yes`.

## What it changes

- Tools are installed with Homebrew (Claude Code, Codex and OpenCode CLIs, beads).
- Claude Code plugins and their marketplaces go to `~/.claude/plugins`, in user scope.
- If chezmoi manages `~/.claude/settings.json`, the bootstrap only downloads plugins and registers
  marketplaces. chezmoi turns plugins on through `enabledPlugins`, so the bootstrap puts
  `settings.json` back after each `claude plugin` command. It warns about installed plugins that
  chezmoi does not turn on, and `make plugins-list` marks them as `off`. Without chezmoi, the
  `claude` CLI turns plugins on as usual.
- Agent Skills are installed globally with `npx skills add -g`.
- codebase-memory-mcp goes to `~/.local/bin`. Its installer also registers the MCP server in the
  agents it finds. Auto-indexing stays off unless you run `make cbm-auto-index`.

## Versions

Everything installs the latest release: Homebrew packages, `skills@latest`, and the
codebase-memory-mcp installer from its `main` branch (a remote script run with `bash`).

To update what is already installed:

```bash
brew upgrade
make plugins-update
make skills-update
make cbm-update
```

## Development

```bash
make lint   # bash -n and shellcheck
make test   # unit tests with stubbed commands, installs nothing
```
