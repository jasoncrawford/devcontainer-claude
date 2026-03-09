# Design: Modular Devcontainer via Published Image + Feature

Date: 2026-03-09

## Problem

The current template-copy model is brittle. When `Dockerfile`, `init-firewall.sh`, mounts, or `postCreateCommand` change in `devcontainer-claude`, the same changes must be manually applied to all four consumer projects (gh-agent, mealplan, site-status, to-dont). This causes drift — to-dont is already missing firewall domains that the template added later.

## Goals

- Changes to the core devcontainer setup only need to be made in one place
- Each project only maintains what genuinely differs: its name, project-specific env tokens, and project-specific firewall domains
- When the core changes, projects benefit on their next container rebuild without any manual edits
- The approach is extensible: new projects can be added trivially

## Solution: Published Image + Devcontainer Feature

Two artifacts are published from `devcontainer-claude` to ghcr.io:

### 1. Base Docker Image (`ghcr.io/jasoncrawford/devcontainer-claude:latest`)

Built from the existing `Dockerfile` and published via GitHub Actions on every push to `main`. Contains all tools (zsh, gh, jq, delta, aggregate, dig, iptables, ipset, etc.) and the `init-firewall.sh` script installed at `/usr/local/bin/`.

Projects that need additional system-level tools (currently only to-dont, which needs Playwright deps and Vercel CLI) use a short local `Dockerfile` that extends the base image rather than duplicating the full Dockerfile.

### 2. Devcontainer Feature (`ghcr.io/jasoncrawford/devcontainer-claude/setup:1`)

A devcontainer feature published alongside the image. Owns all configuration that is currently duplicated in each project's `devcontainer.json`:

- **Mounts**: the full list (claude volume, bash history, skills, commands, settings.json, projects, gitconfig, claude-host bind)
- **Shared containerEnv**: `NODE_OPTIONS`, `CLAUDE_CONFIG_DIR`, `POWERLEVEL9K_DISABLE_GITSTATUS`, `GH_TOKEN`, `VERCEL_TOKEN`
- **postCreateCommand**: `claude plugin install superpowers@claude-plugins-official`
- **postStartCommand**: `.claude.json` copy + `sudo /usr/local/bin/init-firewall.sh`

The feature also reads `/workspace/.devcontainer/firewall-extras.txt` (if present) to inject project-specific domains into the firewall allowlist at container start.

### Per-Project `devcontainer.json` (after migration)

Each project's `devcontainer.json` reduces to only what genuinely varies:

```json
{
  "name": "project-name",
  "image": "ghcr.io/jasoncrawford/devcontainer-claude:latest",
  "runArgs": ["--cap-add=NET_ADMIN", "--cap-add=NET_RAW"],
  "features": {
    "ghcr.io/jasoncrawford/devcontainer-claude/setup:1": {}
  },
  "containerEnv": {
    "PROJECT_SPECIFIC_TOKEN": "${localEnv:PROJECT_SPECIFIC_TOKEN}"
  }
}
```

`runArgs` and per-project `containerEnv` tokens cannot be provided by a feature, so they stay here. `remoteUser`, `workspaceMount`, `workspaceFolder`, `waitFor`, VS Code extensions/settings, and all mounts move into the feature.

### Per-Project `firewall-extras.txt`

A plain text file at `.devcontainer/firewall-extras.txt` listing one domain per line. The postStartCommand reads this file (if it exists) and adds those domains to the firewall allowlist before locking down the network. Projects with no extra domains omit the file or leave it empty.

### to-dont Special Case

to-dont needs Playwright system dependencies and the Vercel CLI, which require root and must be installed at image build time. It keeps a short local `Dockerfile`:

```dockerfile
FROM ghcr.io/jasoncrawford/devcontainer-claude:latest
RUN npx -y playwright install-deps chromium
RUN npm install -g vercel
```

Its `devcontainer.json` uses `"build": { "dockerfile": "Dockerfile" }` instead of `"image"`, otherwise identical to other projects.

## Publishing Infrastructure

Both artifacts are published from the same `devcontainer-claude` repo:

- A new GitHub Actions workflow (`publish.yml`) triggers on push to `main`
- Builds and pushes the Docker image to `ghcr.io/jasoncrawford/devcontainer-claude:latest`
- Packages and publishes the feature to `ghcr.io/jasoncrawford/devcontainer-claude/setup`
- The repo's GitHub Packages permissions need "write packages" granted to Actions

## What Changes in `devcontainer-claude`

- `template/.devcontainer/` is replaced by the feature definition under `src/setup/` (standard devcontainer features layout)
- A `publish.yml` workflow is added alongside the existing `ci.yml`
- `SETUP.md` is updated to reflect the new per-project setup (image reference + feature + optional firewall-extras.txt)
- `test-static.sh` and `test-runtime.sh` are updated to test the feature structure

## What Changes in Each Consumer Project

- `devcontainer.json` slimmed down to name + image/build + runArgs + feature reference + project-specific env tokens
- `Dockerfile` deleted (except to-dont, which gets a short extending Dockerfile)
- `init-firewall.sh` deleted (baked into the image, maintained in devcontainer-claude)
- `firewall-extras.txt` added with project-specific domains

## Tradeoffs / Constraints

- **Version pinning**: using `:latest` means projects always get the newest core on rebuild. This is convenient but means a bad push could break all projects. Alternative: pin to a semver tag and update deliberately. Start with `:latest` and add versioning if it becomes a problem.
- **Private repo**: if `devcontainer-claude` is private, ghcr.io packages are private by default. The container runtime on the host needs to be authenticated (`docker login ghcr.io`). `host-setup.sh` should include this step.
- **Feature limitations**: features cannot add `runArgs` (capabilities), so `--cap-add=NET_ADMIN` and `--cap-add=NET_RAW` must remain in each project's `devcontainer.json`. This is a two-line entry that rarely if ever changes.
- **Cold start**: first container start after a core change pulls a new image layer, which takes time. Subsequent starts are cached.
