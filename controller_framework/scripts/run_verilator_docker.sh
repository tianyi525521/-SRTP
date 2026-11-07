#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "$repo_root:/workspace/SRTP" \
  -w /workspace/SRTP/controller_framework \
  ghcr.io/x-heep/x-heep/x-heep-toolchain:v1.0.6 \
  /bin/bash -lc 'make clean && make test-verilator'
