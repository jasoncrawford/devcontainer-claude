# devcontainer-claude

Template repository for Claude Code devcontainers. Provides a sandboxed Docker environment for running Claude with `--dangerously-skip-permissions`.

## Template Location
`template/.devcontainer/` — copy to a project's `.devcontainer/` and customize per SETUP.md.

## Projects Using This Template
- `~/projects/gh-agent`
- `~/projects/mealplan`
- `~/projects/site-status`
- `~/projects/to-dont`

When updating the template (Dockerfile, devcontainer.json, init-firewall.sh), apply the same changes to all four projects.

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

**Firewall PROJECT DOMAINS**: The `# --- PROJECT DOMAINS ---` comment in `init-firewall.sh` sits inside the `for` loop. Add project-specific domains to the domain list before the closing `; do`.
