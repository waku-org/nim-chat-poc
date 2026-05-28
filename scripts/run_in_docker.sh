#!/usr/bin/env bash
# Run the mix+LEZ chat simulation inside a Docker container (Linux).
#
# The Docker image pre-builds all heavy nix modules. Each sim run clones
# the repo, builds sequencer + run_setup from source (nix-shell), symlinks
# pre-built artifacts, and runs the simulation.
#
# First run: ~60 min (one-time docker build)
# Subsequent runs: ~10 min (clone + sequencer build + sim)
#
# Prerequisites: Docker Desktop running.
#
# Usage:
#   bash scripts/run_in_docker.sh
#   BRANCH=my-branch bash scripts/run_in_docker.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKERFILE="$ROOT/.github/Dockerfile.sim"
IMAGE_NAME="${DOCKER_IMAGE:-ghcr.io/adklempner/logos-chat-sim:latest}"
CONTAINER_NAME="logos-chat-sim-run"
BRANCH="${BRANCH:-feat/sim-rln-gifter-auth-v2}"
REPO_URL="${REPO_URL:-https://github.com/logos-messaging/logos-chat.git}"

# Build image if it doesn't exist or REBUILD_IMAGE=1
if [ "${REBUILD_IMAGE:-0}" = "1" ]; then
    echo "=== Building Docker image locally (~60 min) ==="
    docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$ROOT"
elif ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "=== Pulling Docker image from GHCR ==="
    docker pull "$IMAGE_NAME" || {
        echo "Pull failed, building locally..."
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$ROOT"
    }
else
    echo "=== Docker image cached ==="
fi

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
trap 'echo "=== Rescuing logs ==="; docker cp "$CONTAINER_NAME:/root/logos-chat/simulations/mix_lez_chat/.sim_state" ./docker-sim-logs 2>/dev/null || true; docker rm -f "$CONTAINER_NAME" 2>/dev/null || true' EXIT

echo "=== Starting container ==="
docker run -d --name "$CONTAINER_NAME" "$IMAGE_NAME" tail -f /dev/null

# Stage guest binaries
GUEST_REL="vendor/logos-lez-rln/lez-rln/methods/guest/target/riscv32im-risc0-zkvm-elf/docker"
GUEST_SRC=""
for candidate in \
    "${GUEST_BINARIES_DIR:-}" \
    "$ROOT/$GUEST_REL" \
    "$HOME/Waku/Logos/logos-chat/$GUEST_REL" \
    "../logos-chat/$GUEST_REL"; do
    [ -f "$candidate/rln_registration.bin" ] 2>/dev/null && GUEST_SRC="$candidate" && break
done
if [ -n "$GUEST_SRC" ]; then
    echo "=== Staging guest binaries ==="
    docker exec "$CONTAINER_NAME" mkdir -p "/tmp/guest-bins"
    docker cp "$GUEST_SRC/rln_registration.bin" "$CONTAINER_NAME:/tmp/guest-bins/"
    docker cp "$GUEST_SRC/incremental_merkle_tree.bin" "$CONTAINER_NAME:/tmp/guest-bins/"
fi

# Collect SIM_* env vars
SIM_ENVS=""
for var in $(env | grep '^SIM_' | cut -d= -f1); do
    SIM_ENVS="${SIM_ENVS}export $var='${!var}'; "
done

# Write the run script to the container (avoids heredoc escaping issues)
docker exec -i "$CONTAINER_NAME" bash -c "cat > /root/run-sim.sh && chmod +x /root/run-sim.sh" << 'SIMSCRIPT'
#!/bin/bash
set -euo pipefail

export RISC0_DEV_MODE=1

# Clone repo
cd /root
rm -rf logos-chat
git clone --depth 1 -b "$BRANCH" "$REPO_URL"
cd logos-chat

# Init submodules (lssa needs full history for auto-sync)
git submodule update --init --depth 1
(cd vendor/logos-lez-rln && git submodule update --init lssa && \
    git submodule update --init --depth 1 logos-delivery logos-delivery-module logos-execution-zone-module && \
    git checkout -- . && \
    for d in lssa logos-delivery logos-delivery-module logos-execution-zone-module; do \
        (cd "$d" && git checkout -- .); \
    done)
(cd vendor/logos-lez-rln/logos-delivery-module && git submodule update --init --depth 1 vendor/logos-delivery)

# Symlink pre-built nix modules from image
LEZ_DIR=vendor/logos-lez-rln
ln -sf /root/lez-modules/result-rln $LEZ_DIR/logos-rln-module/result-rln
ln -sf /root/lez-modules/result-wallet $LEZ_DIR/logos-rln-module/result-wallet
mkdir -p $LEZ_DIR/logos-delivery-module/build_plugin
cp -r /root/lez-modules/delivery-plugin $LEZ_DIR/logos-delivery-module/build_plugin/modules
mkdir -p $LEZ_DIR/logos-delivery-module/vendor/logos-delivery/build
cp /root/lez-modules/delivery-build/* $LEZ_DIR/logos-delivery-module/vendor/logos-delivery/build/ 2>/dev/null || true
mkdir -p build
cp /root/lez-modules/liblogoschat.so build/

# Restore guest binaries
GUEST_DIR="$LEZ_DIR/lez-rln/methods/guest/target/riscv32im-risc0-zkvm-elf/docker"
if [ -f /tmp/guest-bins/rln_registration.bin ]; then
    mkdir -p "$GUEST_DIR"
    cp /tmp/guest-bins/*.bin "$GUEST_DIR/"
fi

# Chat module
mkdir -p /root/logos-chat-module
ln -sf /root/lez-modules/chat-module-result /root/logos-chat-module/result

# Build sequencer + run_setup from source (system clang, r0vm in PATH)
echo "Building sequencer + run_setup..."
export LIBCLANG_PATH=/usr/lib/llvm-18/lib
(cd $LEZ_DIR/lssa && cargo build --features standalone -p sequencer_service 2>&1 | tail -3)
(cd $LEZ_DIR/lez-rln && cargo build --bin run_setup 2>&1 | tail -3)

export LOGOSCORE="/root/lez-modules/logoscore-result/bin/logoscore"
bash simulations/mix_lez_chat/run_simulation.sh --fresh
SIMSCRIPT

echo "=== Running simulation ==="
docker exec -e BRANCH="$BRANCH" -e REPO_URL="$REPO_URL" $SIM_ENVS "$CONTAINER_NAME" bash /root/run-sim.sh

echo "=== Done ==="
