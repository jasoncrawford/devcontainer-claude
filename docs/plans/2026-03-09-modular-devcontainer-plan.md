# Modular Devcontainer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace manual template-copy-and-patch across 4 projects with a published Docker base image and devcontainer feature, so core changes only need to be made in one place.

**Architecture:** `devcontainer-claude` publishes two artifacts to ghcr.io: a Docker base image (the current Dockerfile) and a devcontainer feature (`setup`) that provides mounts, shared env, VS Code config, and lifecycle hooks. Consumer projects reference these instead of copying files. Project-specific firewall domains live in `.devcontainer/firewall-extras.txt`.

**Tech Stack:** Docker, GitHub Actions, ghcr.io (GitHub Container Registry), devcontainer Features spec (containers.dev)

**Reference:** Design doc at `docs/plans/2026-03-09-modular-devcontainer-design.md`

---

## Background: Devcontainer Features

A devcontainer feature is a directory with two files:
- `devcontainer-feature.json` — declares metadata, options, and configuration the feature injects into the container (mounts, env vars, VS Code settings, lifecycle hooks, Linux capabilities)
- `install.sh` — a shell script that runs as root at image build time (like a `RUN` step in a Dockerfile); used to install tools

The standard directory layout for a features repo:
```
src/
  <feature-name>/
    devcontainer-feature.json
    install.sh
```

Features are published as OCI artifacts to a container registry. The devcontainers CLI and VS Code handle packaging and publishing via the `devcontainer features publish` command.

**Devcontainer feature spec reference:** https://containers.dev/implementors/features/

Key fields in `devcontainer-feature.json` that are relevant here:
- `capAdd` — Linux capabilities (replaces `--cap-add` in `runArgs`)
- `mounts` — mount definitions (same format as devcontainer.json mounts)
- `containerEnv` — environment variables
- `customizations` — VS Code extensions and settings
- `postCreateCommand`, `postStartCommand`, `waitFor` — lifecycle hooks (merged with any in devcontainer.json)

**Important:** `remoteUser`, `workspaceMount`, and `workspaceFolder` are NOT supported in feature JSON — they must remain in each project's `devcontainer.json`. These are stable fields that rarely change.

---

## Phase 1: Feature Infrastructure in devcontainer-claude

### Task 1: Create the feature directory structure

**Files:**
- Create: `src/setup/devcontainer-feature.json`
- Create: `src/setup/install.sh`

**Step 1: Create directories**
```bash
mkdir -p src/setup
```

**Step 2: Create `src/setup/install.sh`**

The install.sh is minimal — all tools are already in the base image. It just needs to exist and be executable.

```bash
#!/bin/bash
set -e

echo "Claude Code sandbox feature installed."
```

Make it executable:
```bash
chmod +x src/setup/install.sh
```

**Step 3: Create `src/setup/devcontainer-feature.json`**

```json
{
  "id": "setup",
  "version": "1.0.0",
  "name": "Claude Code Sandbox Setup",
  "description": "Mounts, environment, firewall, and VS Code config for Claude Code devcontainers",
  "capAdd": ["NET_ADMIN", "NET_RAW"],
  "mounts": [
    {
      "source": "${containerWorkspaceFolderBasename}-bashhistory-${devcontainerId}",
      "target": "/commandhistory",
      "type": "volume"
    },
    {
      "source": "${containerWorkspaceFolderBasename}-claude-state-${devcontainerId}",
      "target": "/home/node/.claude",
      "type": "volume"
    },
    {
      "source": "${localEnv:HOME}/.claude/skills",
      "target": "/home/node/.claude/skills",
      "type": "bind"
    },
    {
      "source": "${localEnv:HOME}/.claude/commands",
      "target": "/home/node/.claude/commands",
      "type": "bind"
    },
    {
      "source": "${localEnv:HOME}/.claude/settings.json",
      "target": "/home/node/.claude/settings.json",
      "type": "bind"
    },
    {
      "source": "${localEnv:HOME}/.claude/projects",
      "target": "/home/node/.claude/projects",
      "type": "bind"
    },
    {
      "source": "${localEnv:HOME}/.gitconfig",
      "target": "/home/node/.gitconfig",
      "type": "bind",
      "readonly": true
    },
    {
      "source": "${localEnv:HOME}/.claude",
      "target": "/home/node/.claude-host",
      "type": "bind",
      "readonly": true
    }
  ],
  "containerEnv": {
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "POWERLEVEL9K_DISABLE_GITSTATUS": "true",
    "GH_TOKEN": "${localEnv:GH_TOKEN}",
    "VERCEL_TOKEN": "${localEnv:VERCEL_TOKEN}"
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code",
        "dbaeumer.vscode-eslint",
        "esbenp.prettier-vscode",
        "eamodio.gitlens"
      ],
      "settings": {
        "editor.formatOnSave": true,
        "editor.defaultFormatter": "esbenp.prettier-vscode",
        "editor.codeActionsOnSave": {
          "source.fixAll.eslint": "explicit"
        },
        "terminal.integrated.defaultProfile.linux": "zsh",
        "terminal.integrated.profiles.linux": {
          "bash": {
            "path": "bash",
            "icon": "terminal-bash"
          },
          "zsh": {
            "path": "zsh"
          }
        }
      }
    }
  },
  "postCreateCommand": "claude plugin install superpowers@claude-plugins-official",
  "postStartCommand": "cp -n /home/node/.claude-host/.claude.json /home/node/.claude/.claude.json 2>/dev/null; sudo /usr/local/bin/init-firewall.sh",
  "waitFor": "postStartCommand"
}
```

**Step 4: Verify the feature JSON is valid**
```bash
jq . src/setup/devcontainer-feature.json
```
Expected: pretty-printed JSON with no errors.

**Step 5: Commit**
```bash
git add src/setup/
git commit -m "feat: add devcontainer setup feature definition"
```

---

### Task 2: Update init-firewall.sh to read firewall-extras.txt

The `init-firewall.sh` in `template/.devcontainer/` (which gets baked into the image) needs to read project-specific domains from `/workspace/.devcontainer/firewall-extras.txt` at runtime. This replaces the `# --- PROJECT DOMAINS ---` comment block.

**Files:**
- Modify: `template/.devcontainer/init-firewall.sh`

**Step 1: Read the current script to understand the for-loop structure**

Open `template/.devcontainer/init-firewall.sh` and locate lines 65–106 (the domain for-loop). The loop ends with `; do` and the loop body resolves each domain. The `# --- PROJECT DOMAINS ---` comment is currently inside the loop.

**Step 2: Replace the project domains placeholder with an extras-file reader**

After the closing `done` of the main for-loop (currently line 106), add a new block that reads the extras file. Remove the `# --- PROJECT DOMAINS ---` comment inside the loop.

The main for-loop should end cleanly:
```bash
    ; do
    echo "Resolving $domain..."
    # ... rest of loop body unchanged
done
```

After `done`, add:
```bash
# Read project-specific domains from .devcontainer/firewall-extras.txt
EXTRAS_FILE="/workspace/.devcontainer/firewall-extras.txt"
if [ -f "$EXTRAS_FILE" ]; then
    echo "Loading project-specific domains from $EXTRAS_FILE..."
    while IFS= read -r domain || [ -n "$domain" ]; do
        # Skip empty lines and comments
        [[ -z "$domain" || "$domain" =~ ^# ]] && continue
        echo "Resolving extra domain: $domain..."
        ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
        if [ -z "$ips" ]; then
            echo "WARNING: Failed to resolve $domain (skipping)"
            continue
        fi
        while read -r ip; do
            if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "ERROR: Invalid IP from DNS for $domain: $ip"
                exit 1
            fi
            echo "Adding $ip for $domain"
            ipset add allowed-domains "$ip" 2>/dev/null || true
        done < <(echo "$ips")
    done < "$EXTRAS_FILE"
else
    echo "No firewall-extras.txt found, skipping project-specific domains"
fi
```

**Step 3: Run shellcheck on the modified script**
```bash
shellcheck template/.devcontainer/init-firewall.sh
```
Expected: no errors or warnings (check for SC2001 disable comment still present above the sed line).

**Step 4: Commit**
```bash
git add template/.devcontainer/init-firewall.sh
git commit -m "feat: read project-specific firewall domains from firewall-extras.txt"
```

---

### Task 3: Add the GitHub Actions publish workflow

**Files:**
- Create: `.github/workflows/publish.yml`

**Step 1: Enable GitHub Packages write access for Actions**

In the GitHub repo settings:
- Go to Settings → Actions → General → Workflow permissions
- Set to "Read and write permissions"
- Save

This is a one-time manual step in the GitHub UI.

**Step 2: Create `.github/workflows/publish.yml`**

```yaml
name: Publish

on:
  push:
    branches:
      - main

jobs:
  publish-image:
    name: Publish Docker image
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: template/.devcontainer
          file: template/.devcontainer/Dockerfile
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/devcontainer-claude:latest

  publish-feature:
    name: Publish devcontainer feature
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Install devcontainer CLI
        run: npm install -g @devcontainers/cli

      - name: Log in to GitHub Container Registry
        run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

      - name: Publish feature
        run: devcontainer features publish src/ --registry ghcr.io --namespace ${{ github.repository_owner }}/devcontainer-claude
```

**Step 3: Validate the workflow YAML**
```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/publish.yml'))" && echo "VALID"
```
Expected: `VALID`

**Step 4: Commit and push**
```bash
git add .github/workflows/publish.yml
git commit -m "feat: add publish workflow for Docker image and devcontainer feature"
git push
```

**Step 5: Verify the workflow ran**

Go to the GitHub repo → Actions tab. Both `publish-image` and `publish-feature` jobs should complete green. If either fails, read the logs and fix before continuing.

**Step 6: Verify the image is accessible**
```bash
docker pull ghcr.io/jasoncrawford/devcontainer-claude:latest
```
Expected: image downloads successfully.

If the image is private (private repo), you may need to make the package public first:
- Go to GitHub → Packages → devcontainer-claude → Package settings → Change visibility → Public

---

### Task 4: Update test-static.sh

The static test should validate the new feature files.

**Files:**
- Modify: `test-static.sh`

**Step 1: Read the current test-static.sh to understand its structure**

**Step 2: Add validation for the feature files**

After the existing JSON validation block, add:
```bash
echo "Checking feature JSON..."
jq . src/setup/devcontainer-feature.json > /dev/null
echo "Feature JSON valid."

echo "Checking install.sh with shellcheck..."
shellcheck src/setup/install.sh
echo "install.sh OK."
```

**Step 3: Run the updated tests**
```bash
./test-static.sh
```
Expected: all checks pass.

**Step 4: Commit**
```bash
git add test-static.sh
git commit -m "test: validate feature files in test-static.sh"
```

---

### Task 5: Update SETUP.md

Replace the current step-by-step copy instructions with the new minimal setup.

**Files:**
- Modify: `SETUP.md`

**Step 1: Rewrite SETUP.md**

```markdown
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
    "YOUR_PROJECT_TOKEN": "${localEnv:YOUR_PROJECT_TOKEN}"
  },
  "waitFor": "postStartCommand"
}
```

- Change `name` to match your project.
- In `containerEnv`, include only tokens that are set on the host and needed in the container. Remove `YOUR_PROJECT_TOKEN` if you have none. The feature already provides `GH_TOKEN` and `VERCEL_TOKEN`.
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
- **Environment**: `NODE_OPTIONS`, `CLAUDE_CONFIG_DIR`, `GH_TOKEN`, `VERCEL_TOKEN`, `POWERLEVEL9K_DISABLE_GITSTATUS`.
- **VS Code extensions**: Claude Code, ESLint, Prettier, GitLens.
- **Lifecycle**: Plugin install on create; firewall init and `.claude.json` copy on start.
- **Capabilities**: `NET_ADMIN` and `NET_RAW` (required for iptables).

## Running Claude with skip-permissions

```bash
claude --dangerously-skip-permissions
```
```

**Step 2: Commit**
```bash
git add SETUP.md
git commit -m "docs: update SETUP.md for image+feature based setup"
```

---

## Phase 2: Migrate Consumer Projects

> Before migrating: verify the published image and feature are accessible (Task 3, Step 6).

Each migration follows the same pattern: slim down `devcontainer.json`, delete `Dockerfile` and `init-firewall.sh`, add `firewall-extras.txt` with project-specific domains.

---

### Task 6: Migrate gh-agent

**Files in `~/projects/gh-agent/.devcontainer/`:**
- Modify: `devcontainer.json`
- Delete: `Dockerfile`
- Delete: `init-firewall.sh`
- Create: `firewall-extras.txt` (empty, gh-agent has no extra domains)

**Step 1: Replace `devcontainer.json`**

```json
{
  "name": "gh-agent",
  "image": "ghcr.io/jasoncrawford/devcontainer-claude:latest",
  "remoteUser": "node",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/jasoncrawford/devcontainer-claude/setup:1": {}
  },
  "containerEnv": {
    "CLAUDE_CODE_OAUTH_TOKEN": "${localEnv:CLAUDE_CODE_OAUTH_TOKEN}"
  },
  "waitFor": "postStartCommand"
}
```

Note: `CLAUDE_CODE_OAUTH_TOKEN` is gh-agent-specific. `GH_TOKEN` is already provided by the feature.

**Step 2: Create `firewall-extras.txt`**

```
# gh-agent has no extra firewall domains
```

**Step 3: Delete the now-redundant files**
```bash
rm ~/projects/gh-agent/.devcontainer/Dockerfile
rm ~/projects/gh-agent/.devcontainer/init-firewall.sh
```

**Step 4: Validate the new devcontainer.json**
```bash
jq . ~/projects/gh-agent/.devcontainer/devcontainer.json
```
Expected: valid JSON, no errors.

**Step 5: Rebuild and verify the container**

In VS Code with the gh-agent project open, run "Dev Containers: Rebuild Container". Watch the logs to confirm:
- Image pulls from ghcr.io
- Feature installs
- Plugin installs (postCreateCommand)
- Firewall initializes (postStartCommand)
- Firewall reads firewall-extras.txt (look for "No firewall-extras.txt found" or the contents log)

**Step 6: Commit in gh-agent**
```bash
cd ~/projects/gh-agent
git add .devcontainer/
git commit -m "chore: migrate to devcontainer-claude published image and feature"
```

---

### Task 7: Migrate mealplan

**Files in `~/projects/mealplan/.devcontainer/`:**
- Modify: `devcontainer.json`
- Delete: `Dockerfile`, `init-firewall.sh`
- Create: `firewall-extras.txt`

Mealplan uses Supabase and USDA API. From the current `init-firewall.sh`, extra domains are: `supabase.co`, `supabase.com`, `api.nal.usda.gov`.

**Step 1: Replace `devcontainer.json`**

```json
{
  "name": "Claude Code Dev",
  "image": "ghcr.io/jasoncrawford/devcontainer-claude:latest",
  "remoteUser": "node",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/jasoncrawford/devcontainer-claude/setup:1": {}
  },
  "containerEnv": {
    "USDA_API_KEY": "${localEnv:USDA_API_KEY}"
  },
  "waitFor": "postStartCommand"
}
```

**Step 2: Create `firewall-extras.txt`**

```
# Supabase
supabase.co
supabase.com

# USDA Food Data API
api.nal.usda.gov
```

**Step 3: Delete redundant files**
```bash
rm ~/projects/mealplan/.devcontainer/Dockerfile
rm ~/projects/mealplan/.devcontainer/init-firewall.sh
```

**Step 4: Rebuild and verify** (same as Task 6 Step 5, confirm extra domains appear in firewall log)

**Step 5: Commit in mealplan**
```bash
cd ~/projects/mealplan
git add .devcontainer/
git commit -m "chore: migrate to devcontainer-claude published image and feature"
```

---

### Task 8: Migrate site-status

**Files in `~/projects/site-status/.devcontainer/`:**
- Modify: `devcontainer.json`
- Delete: `Dockerfile`, `init-firewall.sh`
- Create: `firewall-extras.txt`

Site-status uses Supabase, Vercel, and Resend. From the current `init-firewall.sh`: `evviomukranebwbwgesa.supabase.co`, `supabase.co`, `supabase.com`, `api.supabase.com`, `vercel.com`, `api.vercel.com`, `vercel.live`, `api.resend.com`.

**Step 1: Replace `devcontainer.json`**

site-status has no project-specific tokens beyond GH_TOKEN (already in feature). No `containerEnv` section needed.

```json
{
  "name": "Site Status Dev",
  "image": "ghcr.io/jasoncrawford/devcontainer-claude:latest",
  "remoteUser": "node",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/jasoncrawford/devcontainer-claude/setup:1": {}
  },
  "waitFor": "postStartCommand"
}
```

**Step 2: Create `firewall-extras.txt`**

```
# Supabase
evviomukranebwbwgesa.supabase.co
supabase.co
supabase.com
api.supabase.com

# Vercel
vercel.com
api.vercel.com
vercel.live

# Resend
api.resend.com
```

**Step 3: Delete redundant files**
```bash
rm ~/projects/site-status/.devcontainer/Dockerfile
rm ~/projects/site-status/.devcontainer/init-firewall.sh
```

**Step 4: Rebuild and verify**

**Step 5: Commit in site-status**
```bash
cd ~/projects/site-status
git add .devcontainer/
git commit -m "chore: migrate to devcontainer-claude published image and feature"
```

---

### Task 9: Migrate to-dont

to-dont needs Playwright system deps and Vercel CLI installed as root at build time, so it keeps a local Dockerfile that extends the base image.

**Files in `~/projects/to-dont/.devcontainer/`:**
- Replace: `Dockerfile` (short, extending base image)
- Modify: `devcontainer.json`
- Delete: `init-firewall.sh`
- Create: `firewall-extras.txt`

**Step 1: Replace `Dockerfile`**

```dockerfile
FROM ghcr.io/jasoncrawford/devcontainer-claude:latest

# Install Playwright Chromium system dependencies (must run as root)
# hadolint ignore=DL3016
RUN npx -y playwright install-deps chromium

# Install Vercel CLI
# hadolint ignore=DL3016
RUN npm install -g vercel
```

**Step 2: Replace `devcontainer.json`**

Uses `build` (not `image`) because of the local Dockerfile.

```json
{
  "name": "To-Don't Dev",
  "build": {
    "dockerfile": "Dockerfile"
  },
  "remoteUser": "node",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=delegated",
  "workspaceFolder": "/workspace",
  "features": {
    "ghcr.io/jasoncrawford/devcontainer-claude/setup:1": {}
  },
  "postCreateCommand": "npm install && npx playwright install chromium && claude plugin install superpowers@claude-plugins-official",
  "waitFor": "postStartCommand"
}
```

Note: `postCreateCommand` here overrides the one from the feature. It extends the base command by adding `npm install && npx playwright install chromium &&` before the plugin install. The feature's postCreateCommand will NOT run separately — the devcontainer spec merges lifecycle commands, but per-project commands take precedence. Keep the full command here.

**Step 3: Create `firewall-extras.txt`**

```
# Supabase
ikhcklpmrmuzgzmfhczj.supabase.co

# Playwright browser downloads
playwright.azureedge.net
playwright-cdn.azureedge.net
```

**Step 4: Delete `init-firewall.sh`**
```bash
rm ~/projects/to-dont/.devcontainer/init-firewall.sh
```

**Step 5: Rebuild and verify**

Confirm Playwright installs and the browser binary is available. Run `npx playwright --version` inside the container.

**Step 6: Commit in to-dont**
```bash
cd ~/projects/to-dont
git add .devcontainer/
git commit -m "chore: migrate to devcontainer-claude published image and feature"
```

---

### Task 10: Update CLAUDE.md and memory

**Files:**
- Modify: `CLAUDE.md`
- Modify: `~/.claude/projects/.../MEMORY.md` (auto-memory for this project)

**Step 1: Update the "Projects Using This Template" section in CLAUDE.md**

Replace the current note about applying changes to all 4 projects with:

```markdown
## Projects Using This Template
- `~/projects/gh-agent`
- `~/projects/mealplan`
- `~/projects/site-status`
- `~/projects/to-dont`

These projects consume the published image and feature from ghcr.io. Changes to `template/.devcontainer/` (Dockerfile, init-firewall.sh) take effect in consumer projects on their next rebuild after the publish workflow runs. No manual file copying needed.

Project-specific config lives in each project's `.devcontainer/firewall-extras.txt`.
```

**Step 2: Remove template directory note from CLAUDE.md**

The `template/.devcontainer/` is still the source for the Dockerfile and init-firewall.sh (used in the build), so keep it referenced but clarify it's the build source, not a file to copy.

**Step 3: Update memory**

Update `~/.claude/projects/.../MEMORY.md` to reflect the new architecture (published image + feature, no more manual copying, firewall-extras.txt per project).

**Step 4: Commit CLAUDE.md**
```bash
cd ~/projects/devcontainer-claude
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md to reflect published image+feature architecture"
```

---

## Verification Checklist

After completing all tasks, verify:

- [ ] `ghcr.io/jasoncrawford/devcontainer-claude:latest` image is publicly accessible
- [ ] `ghcr.io/jasoncrawford/devcontainer-claude/setup:1` feature is publicly accessible
- [ ] All 4 consumer projects rebuild successfully
- [ ] Firewall is active inside each container (`iptables -L OUTPUT` shows DROP policy)
- [ ] Claude can reach `api.anthropic.com` inside each container
- [ ] Project-specific domains in `firewall-extras.txt` are reachable (e.g. Supabase in mealplan)
- [ ] `example.com` is NOT reachable from inside any container
- [ ] Plugin is installed after container create (`claude plugin list` shows superpowers)
- [ ] `./test-static.sh` passes in `devcontainer-claude`

---

## Notes

**Lifecycle command merging:** The devcontainer spec merges lifecycle commands from features and `devcontainer.json`. If both specify `postCreateCommand`, behavior depends on the spec version and client. The plan above handles to-dont's case by putting the full command in `devcontainer.json`. Verify the exact merging behavior if issues arise.

**`capAdd` in features:** The plan uses `capAdd` in `devcontainer-feature.json` to provide `NET_ADMIN` and `NET_RAW`, replacing `runArgs` in each project. If this doesn't work with your devcontainer client version, fall back to adding `"runArgs": ["--cap-add=NET_ADMIN", "--cap-add=NET_RAW"]` to each project's `devcontainer.json`.

**Image visibility:** If `devcontainer-claude` is a private GitHub repo, the ghcr.io packages default to private. Either make them public (GitHub → Packages → Package settings → Change visibility) or ensure `docker login ghcr.io` is run on the host before rebuilding containers. Update `host-setup.sh` to include the login step if keeping private.

**Pinning versions:** The plan uses `:latest` and `:1` (the major version). If a bad push breaks all containers, switch to pinning specific digest SHAs in consumer projects. For a personal project this is likely overkill.
