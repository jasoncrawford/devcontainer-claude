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
