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

# ── Tool presence ─────────────────────────────────────────────────────────────

echo ""
echo "=== Tool presence ==="

if exec_root claude --version &>/dev/null; then
    pass "claude is installed"
else
    fail "claude is not installed"
fi

for tool in git gh jq delta ip6tables iptables ipset; do
    if exec_root command -v "$tool" &>/dev/null; then
        pass "$tool is installed"
    else
        fail "$tool is not installed"
    fi
done

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

# Anthropic endpoint — expect HTTP response (4xx is fine, means firewall passed)
if exec_root curl --connect-timeout 10 -sf -o /dev/null -w "%{http_code}" \
        https://api.anthropic.com 2>/dev/null | grep -qE '^[0-9]+$'; then
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
