#!/bin/bash
# Build cloud_redirect.so for SteamOS using Docker (Ubuntu 22.04, GCC 12).
# Usage: linux-build/build.sh   ->   dist/cloud_redirect.so
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHA="$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
mkdir -p "$ROOT/.cache/linux-build"
docker run --rm ${DOCKER_EXTRA_ARGS:-} \
    -e CR_GIT_SHA="$SHA" \
    -v "$ROOT":/src -v "$ROOT/.cache/linux-build":/work \
    ${BUILD_IMAGE:-ubuntu:22.04} bash /src/linux-build/build-in-container.sh
