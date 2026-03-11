# devcontainer-claude

Template repository for Claude Code devcontainers. Provides a sandboxed Docker environment for running Claude with `--dangerously-skip-permissions`.

## Template Location
`template/.devcontainer/` — the build source for the published Docker image (`ghcr.io/jasoncrawford/devcontainer-claude:latest`) and the devcontainer feature (`src/setup/`). Changes here take effect in consumer projects on their next rebuild after the publish workflow runs.

## Projects Using This Template
- `~/projects/gh-agent`
- `~/projects/mealplan`
- `~/projects/site-status`
- `~/projects/to-dont`

These projects consume the published image and feature from ghcr.io. No manual file copying needed. Project-specific firewall domains live in each project's `.devcontainer/firewall-extras.txt`.

## Testing
```bash
./test-static.sh    # shellcheck + hadolint + JSON validation (requires: brew install shellcheck hadolint)
./test-runtime.sh   # Docker build + firewall assertions (requires Docker with NET_ADMIN/NET_RAW)
```

CI runs `test-static.sh` on every push/PR via `.github/workflows/ci.yml`.

## Key Constraints

**Plugins**: No plugins bind mount. Installed fresh via `postCreateCommand: "claude plugin install superpowers@claude-plugins-official"`. Runs before the firewall is set up (intentional).

**settings.json**: Must exist as a *file* on the host before container start. Run `./host-setup.sh` once to ensure all required host paths exist.

**Volume orphaning**: The `.claude` volume is keyed to `devcontainerId`. Rebuilding after config changes orphans the old volume. Clean up with `docker volume prune`.

**hadolint config**: The `.hadolint.yaml` documents suppressed rules, but hadolint 2.14.0 has a config auto-load bug. Inline `# hadolint ignore=` directives are used in the Dockerfile instead.

**Firewall extras**: Project-specific domains go in `.devcontainer/firewall-extras.txt` (one domain per line, `#` comments supported). The `init-firewall.sh` reads this file at container start from `/workspace/.devcontainer/firewall-extras.txt`.
