#!/usr/bin/env bash
# One-shot: init nested submodules, build all modules, run mix+LEZ chat sim.
#
# Prerequisites: nix (with flakes), Docker, cargo-risczero.
#
# Environment variables:
#   CHAT_MODULE_DIR    — path to logos-chat-module checkout (default: ../logos-chat-module)
#   CHAT_MODULE_REPO   — git URL to clone if CHAT_MODULE_DIR doesn't exist
#   CHAT_MODULE_BRANCH — branch to clone (default: feat/logos-delivery)
#   SIM_*              — simulation parameters, see run_simulation.sh / README.md
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHAT_MODULE_DIR="${CHAT_MODULE_DIR:-$ROOT/../logos-chat-module}"
CHAT_MODULE_REPO="${CHAT_MODULE_REPO:-git@github.com:adklempner/logos-chat-module.git}"
CHAT_MODULE_BRANCH="${CHAT_MODULE_BRANCH:-feat/logos-delivery}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

cd "$ROOT"

# Docker/CI: nix can't sandbox inside containers. Remove /homeless-shelter
# (nix's sandbox HOME stub) and export NIX_CONFIG to disable sandboxing.
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    rmdir /homeless-shelter 2>/dev/null || true
    export NIX_CONFIG="sandbox = false
${NIX_CONFIG:-}"
fi

# On Linux with nix, bindgen (used by rocksdb/sequencer) needs LIBCLANG_PATH
# and system headers. This covers both Docker and native nix-on-Linux.
if [ "$(uname -s)" = "Linux" ] && [ -d /nix/store ] && [ -z "${LIBCLANG_PATH:-}" ]; then
    CLANG_SO=$(find /nix/store -maxdepth 3 -name 'libclang.so' 2>/dev/null | head -1 || true)
    if [ -n "$CLANG_SO" ]; then
        export LIBCLANG_PATH=$(dirname "$CLANG_SO")
        STDBOOL=$(find "$LIBCLANG_PATH" -maxdepth 5 -name 'stdbool.h' 2>/dev/null | head -1 || true)
        [ -n "$STDBOOL" ] && export BINDGEN_EXTRA_CLANG_ARGS="-I$(dirname "$STDBOOL")"
    fi
    log "Docker detected — disabled nix sandbox, LIBCLANG_PATH=$LIBCLANG_PATH"
fi

# 1. Init submodules. Top-level first (non-recursive to avoid circular refs
#    in vendor/logos-lez-rln), then nwaku/nimbus-build-system recursively,
#    then logos-lez-rln's nested submodules selectively.
log "Initializing top-level submodules..."
git submodule update --init
(cd vendor/nwaku && git submodule update --init --recursive)
(cd vendor/nimbus-build-system && git submodule update --init --recursive)

# Init nested submodules inside vendor/logos-lez-rln non-recursively
#    (recursive init hits circular submodule references).
#    Preserve pre-built guest binaries across submodule reset (they're
#    architecture-independent RISC-V ELFs that take ~10min to rebuild).
GUEST_DIR="vendor/logos-lez-rln/lez-rln/methods/guest/target/riscv32im-risc0-zkvm-elf/docker"
# Check repo tree first, then /tmp/guest-bins/ (staged by run_in_docker.sh)
GUEST_TMP=""
if [ -f "$GUEST_DIR/rln_registration.bin" ]; then
    GUEST_TMP=$(mktemp -d)
    cp "$GUEST_DIR"/*.bin "$GUEST_TMP/"
    log "Preserved guest binaries from repo"
elif [ -f "/tmp/guest-bins/rln_registration.bin" ]; then
    GUEST_TMP="/tmp/guest-bins"
    log "Using guest binaries from /tmp/guest-bins/"
fi
log "Initializing nested submodules in vendor/logos-lez-rln..."
# Slim default: only logos-delivery-module (+ its nested logos-delivery) is
# required to build the chat/delivery/mix Nim modules. lssa and
# logos-execution-zone-module are fetched via flake.nix from GitHub when nix
# builds the wallet/rln modules, so the local clones aren't needed unless the
# dev is running a local sequencer (SIM_NETWORK=local) or hacking those repos.
SUBMODS=(logos-delivery-module)
if [ "${SIM_NETWORK:-testnet}" = "local" ] || [ "${SIM_FULL_SUBMODS:-0}" = "1" ]; then
    SUBMODS+=(lssa logos-execution-zone-module)
fi
(cd vendor/logos-lez-rln && \
    git submodule update --init "${SUBMODS[@]}" && \
    git checkout -- . && \
    for d in "${SUBMODS[@]}"; do \
        (cd "$d" && git checkout -- .); \
    done && \
    cd logos-delivery-module && git submodule update --init vendor/logos-delivery)
if [ -d "${GUEST_TMP:-}" ]; then
    mkdir -p "$GUEST_DIR"
    cp "$GUEST_TMP"/*.bin "$GUEST_DIR/"
    rm -rf "$GUEST_TMP"
    log "Restored guest binaries"
fi

# 2. Build LEZ modules (RLN, wallet, delivery plugin, guest zkVM binaries).
log "Building LEZ modules via vendor/logos-lez-rln/build_all.sh..."
bash vendor/logos-lez-rln/build_all.sh

# 3. Build liblogoschat (Nim shared library).
log "Building liblogoschat..."
make update
make liblogoschat

# 4. Clone and build logos-chat-module (C++ Qt plugin).
if [ ! -d "$CHAT_MODULE_DIR" ]; then
    log "Cloning logos-chat-module to $CHAT_MODULE_DIR..."
    git clone -b "$CHAT_MODULE_BRANCH" "$CHAT_MODULE_REPO" "$CHAT_MODULE_DIR"
fi
log "Building logos-chat-module..."
(cd "$CHAT_MODULE_DIR" && nix build)

# 5. Run the simulation.
log "Starting mix+LEZ chat simulation..."
exec bash "$ROOT/simulations/mix_lez_chat/run_simulation.sh" --fresh "$@"
