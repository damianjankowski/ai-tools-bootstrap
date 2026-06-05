# dj-sre-kit bootstrap

Interactive bootstrap scripts for setting up Claude Code and related tooling on a new machine.

## Quick start

```bash
make bootstrap        # Claude Code tools + plugins
make bootstrap-codex  # Codex tools + plugins
```

Requires `dialog` for the TUI checklist (`brew install dialog`). Falls back to a text prompt if absent.
