#!/bin/bash
# Runtime tests — requires Docker with NET_ADMIN/NET_RAW capability and internet access.
# NOT suitable for standard GitHub Actions runners. Run locally.
set -uo pipefail

IMAGE="devcontainer-claude-test"
CONTAINER="devcontainer-claude-test-run"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    docker rm -f "$CONTAINER" 2>/dev/null && echo "  Removed container" || true
    docker rmi -f "$IMAGE" 2>/dev/null && echo "  Removed image" || true
}
trap cleanup EXIT

# ── Tool checks ──────────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker not found."
    exit 1
fi

# ── Build ────────────────────────────────────────────────────────────────────

echo ""
echo "=== Build ==="
if docker build \
    --build-arg TZ=UTC \
    --build-arg CLAUDE_CODE_CHANNEL=latest \
    --build-arg GIT_DELTA_VERSION=0.18.2 \
    --build-arg ZSH_IN_DOCKER_VERSION=1.2.0 \
    -t "$IMAGE" \
    template/.devcontainer/; then
    pass "docker build succeeds"
else
    fail "docker build failed — aborting runtime tests"
    exit 1
fi

# ── Start container ───────────────────────────────────────────────────────────

echo ""
echo "=== Starting container ==="
docker run -d \
    --name "$CONTAINER" \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    --user root \
    "$IMAGE" \
    sleep 300

exec_root() { docker exec --user root "$CONTAINER" "$@"; }
exec_node() { docker exec --user node "$CONTAINER" "$@"; }

# ── Script presence ───────────────────────────────────────────────────────────

echo ""
echo "=== Script presence ==="
for script in init-firewall.sh post-create.sh post-start.sh; do
    if exec_root test -x "/usr/local/bin/$script"; then
        pass "$script is present and executable"
    else
        fail "$script is missing or not executable"
    fi
done

# ── .claude.json seeding ──────────────────────────────────────────────────────

echo ""
echo "=== .claude.json seeding ==="

exec_root mkdir -p /home/node/.claude-host /home/node/.claude
exec_root chown -R node:node /home/node/.claude-host /home/node/.claude

# Inline the seeding logic from post-create.sh so we can test it without
# running the full script (plugin install requires Claude auth).
seed() {
    exec_node bash -c '
        if [ -f /home/node/.claude-host/.claude.json ] && [ ! -f /home/node/.claude/.claude.json ]; then
            cp /home/node/.claude-host/.claude.json /home/node/.claude/.claude.json
        fi'
}

# Case 1: source exists, dest doesn't → should copy
exec_node bash -c 'echo "{\"hasCompletedOnboarding\":true}" > /home/node/.claude-host/.claude.json'
seed
if exec_node jq -e '.hasCompletedOnboarding == true' /home/node/.claude/.claude.json &>/dev/null; then
    pass "seeds .claude.json when source exists and dest does not"
else
    fail "failed to seed .claude.json from source"
fi

# Case 2: both exist → dest should NOT be overwritten (rebuild/restart case)
exec_node bash -c 'echo "{\"hasCompletedOnboarding\":false}" > /home/node/.claude-host/.claude.json'
seed
if exec_node jq -e '.hasCompletedOnboarding == true' /home/node/.claude/.claude.json &>/dev/null; then
    pass "preserves existing .claude.json when dest already exists (rebuild case)"
else
    fail "overwrote existing .claude.json on rebuild"
fi

# Case 3: source missing → dest should not be created
exec_root rm /home/node/.claude/.claude.json /home/node/.claude-host/.claude.json
seed
if exec_node bash -c '[ ! -f /home/node/.claude/.claude.json ]'; then
    pass "skips seeding when source is missing"
else
    fail "created .claude.json despite missing source"
fi

# ── Tool presence ─────────────────────────────────────────────────────────────

echo ""
echo "=== Tool presence ==="

if exec_root claude --version &>/dev/null; then
    pass "claude is installed"
else
    fail "claude is not installed"
fi

for tool in git gh jq delta ip6tables iptables ipset; do
    if exec_root which "$tool" &>/dev/null; then
        pass "$tool is installed"
    else
        fail "$tool is not installed"
    fi
done

# ── node_modules volume isolation ─────────────────────────────────────────────
# Verifies that a named volume at /workspace/node_modules shadows broken host
# node_modules (darwin binaries) and allows native modules to run inside the
# Linux container after a fresh npm install.

echo ""
echo "=== node_modules volume isolation ==="

NM_WORKSPACE=$(mktemp -d)
NM_VOL="devcontainer-test-node-modules-$$"

# Minimal package.json with esbuild — a native module that fails with wrong-platform binaries.
cat > "$NM_WORKSPACE/package.json" << 'JSON'
{"dependencies":{"esbuild":"*"}}
JSON

# Simulate darwin host node_modules: a fake esbuild that throws a platform error.
mkdir -p "$NM_WORKSPACE/node_modules/esbuild/lib"
cat > "$NM_WORKSPACE/node_modules/esbuild/package.json" << 'JSON'
{"name":"esbuild","version":"0.0.0","main":"lib/main.js"}
JSON
cat > "$NM_WORKSPACE/node_modules/esbuild/lib/main.js" << 'JS'
throw new Error("esbuild: darwin-arm64 binary — wrong platform for linux-x64")
JS

# Step 1: without the volume, the broken host node_modules should cause failure.
if docker run --rm \
    -v "$NM_WORKSPACE:/workspace" \
    -w /workspace \
    --user node \
    "$IMAGE" \
    node -e 'require("esbuild")' > /dev/null 2>&1; then
    fail "broken host node_modules should have failed but did not"
else
    pass "broken host node_modules correctly fail without volume mount"
fi

# Step 2: with the volume shadowing and a fresh npm install inside the container,
# esbuild (linux-x64) should load successfully.
docker volume create "$NM_VOL" > /dev/null
if docker run --rm \
    -v "$NM_WORKSPACE:/workspace" \
    -v "$NM_VOL:/workspace/node_modules" \
    -w /workspace \
    --user node \
    "$IMAGE" \
    bash -c "npm install --silent 2>/dev/null && node -e 'require(\"esbuild\")'" > /dev/null 2>&1; then
    pass "esbuild loads after volume shadows broken host node_modules and npm install runs"
else
    fail "esbuild failed despite node_modules volume mount and npm install"
fi

docker volume rm "$NM_VOL" > /dev/null 2>&1 || true
rm -rf "$NM_WORKSPACE"

# ── Firewall setup ────────────────────────────────────────────────────────────

echo ""
echo "=== Firewall setup ==="
if exec_root /usr/local/bin/init-firewall.sh; then
    pass "init-firewall.sh exits 0"
else
    fail "init-firewall.sh failed — skipping firewall assertions"
    exit 1
fi

# ── Firewall: blocked domains ─────────────────────────────────────────────────

echo ""
echo "=== Firewall: blocked ==="
for domain in "https://example.com" "https://google.com" "https://cloudflare.com"; do
    if exec_root curl --connect-timeout 5 -s "$domain" &>/dev/null; then
        fail "$domain should be blocked"
    else
        pass "$domain is blocked"
    fi
done

# ── Firewall: allowed domains ─────────────────────────────────────────────────

echo ""
echo "=== Firewall: allowed ==="
for domain in "https://api.github.com/zen" "https://registry.npmjs.org/"; do
    if exec_root curl --connect-timeout 10 -sf "$domain" &>/dev/null; then
        pass "$domain is reachable"
    else
        fail "$domain should be reachable"
    fi
done

# Anthropic endpoint — any HTTP response (including 4xx) means firewall passed
http_code=$(exec_root curl --connect-timeout 10 -s -o /dev/null -w "%{http_code}" \
    https://api.anthropic.com 2>/dev/null || true)
if [[ "$http_code" =~ ^[0-9]+$ ]] && [[ "$http_code" != "000" ]]; then
    pass "api.anthropic.com is reachable"
else
    fail "api.anthropic.com should be reachable"
fi

# ── Firewall: DNS ─────────────────────────────────────────────────────────────

echo ""
echo "=== Firewall: DNS ==="
if exec_root dig +short A github.com | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "DNS resolution works (github.com)"
else
    fail "DNS resolution failed"
fi

# ── Firewall: IPv6 blocked ────────────────────────────────────────────────────

echo ""
echo "=== Firewall: IPv6 ==="
if exec_root ip6tables -L INPUT -n | grep -q "policy DROP"; then
    pass "ip6tables INPUT policy is DROP"
else
    fail "ip6tables INPUT policy should be DROP"
fi
if exec_root ip6tables -L OUTPUT -n | grep -q "policy DROP"; then
    pass "ip6tables OUTPUT policy is DROP"
else
    fail "ip6tables OUTPUT policy should be DROP"
fi

# ── Firewall: ipset populated ─────────────────────────────────────────────────

echo ""
echo "=== Firewall: ipset ==="
if exec_root ipset list allowed-domains &>/dev/null; then
    pass "ipset 'allowed-domains' exists"
    count=$(exec_root ipset list allowed-domains | grep -cE '^[0-9]+\.' || true)
    if [[ "$count" -gt 10 ]]; then
        pass "ipset has $count entries (expected >10)"
    else
        fail "ipset has only $count entries (expected >10)"
    fi
else
    fail "ipset 'allowed-domains' not found"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
