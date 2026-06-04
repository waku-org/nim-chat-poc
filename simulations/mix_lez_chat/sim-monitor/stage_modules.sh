#!/usr/bin/env bash
# Stage chat backend modules for the monitor's --host-chat mode.
# Extracts .lgx bundles, applies dylib overrides, copies basecamp's
# capability_module + logos_host, and sets up LOGOS_USER_DIR.
#
# Usage:
#   bash stage_modules.sh <output_dir>
#   LOGOS_USER_DIR=<output_dir> ./build/sim-monitor --host-chat ...
set -euo pipefail

die() { echo "FATAL: $*" >&2; exit 1; }

OUTDIR="${1:?Usage: stage_modules.sh <output_dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGOS_CHAT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  PLATFORM="darwin-arm64-dev"; EXT="dylib";;
    Linux-x86_64)  PLATFORM="linux-x86_64-dev"; EXT="so";;
    Linux-aarch64) PLATFORM="linux-aarch64-dev"; EXT="so";;
    *) die "Unsupported platform: $(uname -s)-$(uname -m)";;
esac

# ─── .lgx pins (override via env) ───
WALLET_LGX="${WALLET_LGX:-/nix/store/n6i91xn2c8i0mf71jv9kdsrrgf322cpq-logos-execution-zone-module-lgx-dev/logos-execution-zone-module.lgx}"
RLN_LGX="${RLN_LGX:-/nix/store/ha0j889lmg87r7bmcl3yqkz8j8nb1527-logos-rln-module-lgx-dev/logos-rln-module.lgx}"
CHAT_LGX="${CHAT_LGX:-/nix/store/7zqyg5vmi34cnw4k1za3m5lkhh99c0dq-logos-chat_module-module-lib-lgx-1.0.0/logos-chat_module-module-lib.lgx}"

# Basecamp store path (for capability_module + logos_host + liblogos_core)
BASECAMP="${BASECAMP:-/nix/store/5qry4yw3zf6vg7xbck0xgk9rw7wyf322-logos-basecamp-0.0.0-dev}"

# Dylib overrides
DELIVERY_EXTRA_LIB="${DELIVERY_EXTRA_LIB:-$LOGOS_CHAT_DIR/vendor/logos-lez-rln/logos-delivery/build/liblogosdelivery.$EXT}"
CHAT_EXTRA_LIB="${CHAT_EXTRA_LIB:-}"

install_lgx() {
    local mdir="$1" lgx="$2"
    local name
    name=$(tar xzOf "$lgx" manifest.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
    [ -z "$name" ] && die "install_lgx: cannot read name from $lgx"
    local tmp; tmp=$(mktemp -d)
    tar xzf "$lgx" -C "$tmp"
    rm -rf "$mdir/$name"; mkdir -p "$mdir/$name"
    cp "$tmp/manifest.json" "$mdir/$name/"
    [ -d "$tmp/variants/$PLATFORM" ] || die "install_lgx: $PLATFORM variant missing in $lgx"
    cp -L "$tmp"/variants/"$PLATFORM"/* "$mdir/$name/"
    printf '%s' "$PLATFORM" > "$mdir/$name/variant"
    rm -rf "$tmp"
    echo "  Staged: $name"
}

resign() { [ "$(uname -s)" = "Darwin" ] && codesign --force --sign - "$1" 2>/dev/null || true; }

# ─── Create output structure ───
MODULES="$OUTDIR/modules"
mkdir -p "$MODULES" "$OUTDIR/module_data" "$OUTDIR/bin"

# ─── capability_module from basecamp ───
echo "=== Staging capability_module ==="
[ -d "$BASECAMP/modules/capability_module" ] || die "capability_module not found in $BASECAMP"
cp -r "$BASECAMP/modules/capability_module" "$MODULES/"
echo "  Staged: capability_module"

# ─── logos_host + liblogos_core from basecamp ───
echo "=== Staging runtime binaries ==="
cp -L "$BASECAMP/bin/logos_host" "$OUTDIR/bin/"; resign "$OUTDIR/bin/logos_host"
cp -L "$BASECAMP/lib/liblogos_core.$EXT" "$OUTDIR/bin/"; resign "$OUTDIR/bin/liblogos_core.$EXT"
[ -f "$BASECAMP/lib/libpackage_manager_lib.$EXT" ] && cp -L "$BASECAMP/lib/libpackage_manager_lib.$EXT" "$OUTDIR/bin/"
echo "  logos_host + liblogos_core → $OUTDIR/bin/"

# ─── Chat backend modules from .lgx ───
echo "=== Staging .lgx modules ==="
install_lgx "$MODULES" "$WALLET_LGX"
install_lgx "$MODULES" "$RLN_LGX"
install_lgx "$MODULES" "$CHAT_LGX"

# ─── Dylib overrides ───
echo "=== Applying dylib overrides ==="
if [ -n "$CHAT_EXTRA_LIB" ] && [ -f "$CHAT_EXTRA_LIB" ]; then
    cp -L "$CHAT_EXTRA_LIB" "$MODULES/chat_module/liblogoschat.$EXT"
    resign "$MODULES/chat_module/liblogoschat.$EXT"
    echo "  Override: liblogoschat.$EXT (from CHAT_EXTRA_LIB)"
fi

echo ""
echo "=== Done ==="
echo "  Modules: $MODULES"
echo "  Binaries: $OUTDIR/bin"
echo ""
echo "Launch monitor in host mode:"
echo "  LOGOS_USER_DIR=$OUTDIR LOGOS_HOST_PATH=$OUTDIR/bin/logos_host \\"
echo "    ./build/sim-monitor --host-chat --state-dir .sim_state"
