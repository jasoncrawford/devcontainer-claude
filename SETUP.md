# Devcontainer Setup Instructions

Instructions for setting up a Claude Code devcontainer in a new project using this template.

## Steps

### 1. Copy the template

Copy the `.devcontainer/` directory from this repo's `template/` folder into the root of the target project:

```bash
cp -r /path/to/devcontainer-claude/template/.devcontainer /path/to/target-project/.devcontainer
```

### 2. Update the project name

In `.devcontainer/devcontainer.json`, update the `name` field to match the project:

```json
"name": "Your Project Name"
```

### 3. Add project-specific firewall domains

In `.devcontainer/init-firewall.sh`, find the `PROJECT DOMAINS` comment and add any domains the project needs outbound access to. Common ones by stack:

- **Supabase**: `your-project-ref.supabase.co`
- **Vercel API**: `api.vercel.com`
- **Stripe**: `api.stripe.com`
- **Resend**: `api.resend.com`
- **OpenAI**: `api.openai.com`
- **Fly.io**: `api.fly.io`

Example:
```bash
    # --- PROJECT DOMAINS ---
    "your-project-ref.supabase.co" \
    "api.stripe.com" \
```

### 4. Update environment variables

In `.devcontainer/devcontainer.json`, review the `containerEnv` section. Remove tokens that don't apply and add any the project needs:

```json
"containerEnv": {
  "NODE_OPTIONS": "--max-old-space-size=4096",
  "CLAUDE_CONFIG_DIR": "/home/node/.claude",
  "POWERLEVEL9K_DISABLE_GITSTATUS": "true",
  "GH_TOKEN": "${localEnv:GH_TOKEN}",
  "VERCEL_TOKEN": "${localEnv:VERCEL_TOKEN}",
  "SUPABASE_ACCESS_TOKEN": "${localEnv:SUPABASE_ACCESS_TOKEN}"
}
```

Only include tokens that are actually set in the host environment and needed inside the container.

### 5. Add project-specific VS Code extensions

In `.devcontainer/devcontainer.json`, add any language or framework extensions under `customizations.vscode.extensions`. The template includes a baseline set (Claude Code, ESLint, Prettier, GitLens). Common additions:

- **TypeScript/Next.js**: already covered by baseline
- **Python**: `ms-python.python`
- **Tailwind**: `bradlc.vscode-tailwindcss`
- **Prisma**: `Prisma.prisma`

### 6. Ensure host directories exist

The container bind-mounts several directories from the host. Make sure these exist before starting the container:

```bash
mkdir -p ~/.claude/skills ~/.claude/commands ~/.claude/projects ~/.claude/plugins
```

`settings.json` and `.gitconfig` should already exist if Claude Code and git are configured on the host.

## What the template provides

- **Firewall** (`init-firewall.sh`): Restricts outbound traffic to an allowlist using iptables/ipset. GitHub IP ranges are fetched dynamically; other domains are resolved at startup. Runs as root via a sudoers rule.
- **Persistent state**: Claude's state (`.claude/`) is stored in a named Docker volume per project, so it survives container rebuilds.
- **Shared config**: Skills, commands, settings, and projects are bind-mounted read-write from the host, so changes inside the container are reflected on the host and vice versa.
- **Shell**: zsh with Powerlevel10k, fzf, and git plugins.
- **Tools**: git, gh, jq, vim, nano, delta (git diff), and standard build tools.

## Running Claude with skip-permissions

Once the container is running, Claude Code can be launched with:

```bash
claude --dangerously-skip-permissions
```

The firewall ensures that even with permissions skipped, outbound network access is restricted to the allowlist.
