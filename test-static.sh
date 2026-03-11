#!/bin/bash
# Static analysis tests — safe to run in CI (no Docker required).
# Checks: shellcheck, hadolint, JSON validation.
set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

run() {
    local label="$1"; shift
    if "$@" 2>&1; then
        pass "$label"
    else
        fail "$label"
    fi
}

# ── Tool checks ──────────────────────────────────────────────────────────────

require() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' not found. Install it and re-run."
        exit 1
    fi
}

require shellcheck
require hadolint
require jq

# ── Tests ────────────────────────────────────────────────────────────────────

echo ""
echo "=== JSON validation ==="
run "template/devcontainer.json is valid JSON" \
    jq empty template/.devcontainer/devcontainer.json

echo ""
echo "=== Script consistency ==="
# Verify scripts referenced by devcontainer.json exist in the template.
for script in post-create.sh post-start.sh; do
    run "$script exists in template" \
        test -f "template/.devcontainer/$script"
done

echo ""
echo "=== Dockerfile linting (hadolint) ==="
run "template/Dockerfile" \
    hadolint template/.devcontainer/Dockerfile

echo ""
echo "=== Feature validation ==="
run "src/setup/devcontainer-feature.json is valid JSON" \
    jq empty src/setup/devcontainer-feature.json
run "src/setup/install.sh passes shellcheck" \
    shellcheck src/setup/install.sh

# Feature containerEnv values are injected as ENV instructions in Dockerfile.extended
# at Docker build time. ${localEnv:...} substitutions are NOT resolved at that phase —
# they're only resolved for devcontainer.json-level containerEnv at container creation.
# Using ${localEnv:...} in a feature's containerEnv causes a Docker BuildKit error.
localenv_hits=$(jq -r '.containerEnv | to_entries[].value' src/setup/devcontainer-feature.json \
    | grep -c "\${localEnv:" || true)
if [[ "$localenv_hits" -gt 0 ]]; then
    fail "feature containerEnv has ${localenv_hits} \${localEnv:...} value(s) — not resolved at Docker build time"
else
    pass "feature containerEnv has no \${localEnv:...} values"
fi

echo ""
echo "=== Shell script linting (shellcheck) ==="
run "template/init-firewall.sh" \
    shellcheck template/.devcontainer/init-firewall.sh
run "template/post-create.sh" \
    shellcheck template/.devcontainer/post-create.sh
run "template/post-start.sh" \
    shellcheck template/.devcontainer/post-start.sh
run "host-setup.sh" \
    shellcheck host-setup.sh
run "test-static.sh" \
    shellcheck test-static.sh

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
