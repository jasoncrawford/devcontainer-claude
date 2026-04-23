#!/bin/bash
# Workaround for @anthropic-ai/claude-agent-sdk on glibc systems.
#
# The SDK's native-binary probe tries the musl variant first and only falls
# back to the glibc variant if require.resolve() on the musl package throws.
# The musl package manifests don't declare "libc": ["musl"], so npm installs
# both variants on any Linux system — and the SDK then picks musl, which
# fails its dynamic link against glibc, crashing the subprocess on first
# write (EPIPE on the stdin socket).
#
# This image is always Debian/glibc (FROM node:20), so the musl variants are
# never correct here. Remove them so the SDK's fallback picks the glibc binary.
#
# Projects that depend on @anthropic-ai/claude-agent-sdk should invoke this
# in their postCreateCommand after npm ci, e.g.:
#     "postCreateCommand": "npm ci && claude-sdk-fix-libc"
#
# Safe to run in projects that don't use the SDK — the glob is a no-op if the
# paths don't exist.
set -euo pipefail

if [ -d node_modules/@anthropic-ai ]; then
    rm -rf node_modules/@anthropic-ai/claude-agent-sdk-linux-x64-musl \
           node_modules/@anthropic-ai/claude-agent-sdk-linux-arm64-musl
fi
