#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${1:-$SCRIPT_DIR/.sim_state}"

if [ ! -f "$SCRIPT_DIR/build/sim-monitor" ]; then
    echo "Building sim-monitor..."
    (cd "$SCRIPT_DIR" && nix develop --command bash -c "cmake -B build -GNinja && cmake --build build")
fi

exec nix develop "$SCRIPT_DIR" --command "$SCRIPT_DIR/build/sim-monitor" --state-dir "$STATE_DIR"
