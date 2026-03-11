# Devcontainer Setup Instructions

Instructions for setting up a Claude Code devcontainer in a new project.

## Prerequisites

Run this once on the host machine (creates required directories and files):

```bash
./host-setup.sh
```

## Steps

### 1. Create `.devcontainer/devcontainer.json`

Copy and customize:

```json
{
  "name": "Your Project Name",
  "image": "ghcr.io/jasoncrawford/devcontainer-claude:latest",
  "remoteUser": "node",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/jasoncrawford/devcontainer-claude/setup:1": {}
  },
  "containerEnv": {
    "GH_TOKEN": "${localEnv:GH_TOKEN}",
    "VERCEL_TOKEN": "${localEnv:VERCEL_TOKEN}",
    "CLAUDE_CODE_OAUTH_TOKEN": "${localEnv:CLAUDE_CODE_OAUTH_TOKEN}"
  },
  "waitFor": "postStartCommand"
}
```

- Change `name` to match your project.
- The three `containerEnv` entries are required — they pass auth tokens from your host environment into the container in memory (no files). Add any project-specific tokens alongside them.
- `remoteUser`, `workspaceMount`, `workspaceFolder`, and `waitFor` are the same for all projects — copy verbatim.

### 2. Add project-specific firewall domains (if needed)

Create `.devcontainer/firewall-extras.txt` with one domain per line:

```
# Supabase
your-project-ref.supabase.co
supabase.co
supabase.com

# Other services
api.stripe.com
```

Omit this file if the project needs no extra domains beyond the defaults (GitHub, npm, Anthropic, VS Code).

### 3. For projects needing extra system packages

If the project needs tools that must be installed as root (e.g. Playwright system deps), add a short `.devcontainer/Dockerfile` that extends the base:

```dockerfile
FROM ghcr.io/jasoncrawford/devcontainer-claude:latest
RUN npx -y playwright install-deps chromium
```

Then change `devcontainer.json` to use `build` instead of `image`:

```json
"build": {
  "dockerfile": "Dockerfile"
}
```

## What the feature provides

Automatically, without any configuration in the project:

- **Firewall** (`init-firewall.sh`): Restricts outbound traffic to an allowlist (GitHub, npm, Anthropic API, VS Code). Reads `.devcontainer/firewall-extras.txt` for project-specific domains.
- **Mounts**: `.claude` volume (per project, keyed to devcontainerId), plus bind mounts for skills, commands, settings.json, projects, gitconfig, and `.claude-host`.
- **Environment**: `NODE_OPTIONS`, `CLAUDE_CONFIG_DIR`, `POWERLEVEL9K_DISABLE_GITSTATUS`. Auth tokens (`GH_TOKEN`, `VERCEL_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`) must be set in each project's `containerEnv` — the feature cannot inject host env vars at Docker build time.
- **VS Code extensions**: Claude Code, ESLint, Prettier, GitLens.
- **Lifecycle**: On create, runs `/usr/local/bin/post-create.sh` (seeds `.claude.json` from host, installs superpowers plugin). On start, runs `/usr/local/bin/post-start.sh` (runs the firewall script). Both scripts are baked into the base image.
- **Capabilities**: `NET_ADMIN` and `NET_RAW` (required for iptables).

## Running Claude with skip-permissions

```bash
claude --dangerously-skip-permissions
```
