# devcontainer-claude

A sandboxed Docker environment for running [Claude Code](https://claude.ai/code) with `--dangerously-skip-permissions` — safely.

The container runs with an outbound firewall (allowlist-only), so Claude can browse docs and push code, but can't reach arbitrary internet hosts. Superpowers plugins are installed automatically on first start.

## What you get

- Outbound firewall: GitHub, npm, VS Code, and Claude's required domains — everything else blocked
- IPv6 fully blocked
- Superpowers plugins pre-installed
- Persistent `.claude` volume so Claude's memory survives container restarts
- Safe to run with `--dangerously-skip-permissions`

## Quick start

1. Copy `template/.devcontainer/` into your project's `.devcontainer/`
2. Run `./host-setup.sh` once on your host machine (creates required paths)
3. Open the project in VS Code and **Reopen in Container**

Claude starts with plugins installed and the firewall active.

## Customization

See `SETUP.md` for how to add project-specific allowed domains, adjust mounts, and configure Claude settings.

## Requirements

- Docker (with `NET_ADMIN` and `NET_RAW` capabilities)
- [VS Code Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
