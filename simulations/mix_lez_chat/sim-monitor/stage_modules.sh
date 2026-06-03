#!/usr/bin/env bash
# Stage .lgx modules + basecamp's capability_module into a directory
# suitable for logos_core_add_modules_dir(). Applies Phase 0.3 dylib
# overrides and ad-hoc codesigns.
#
# Usage:
#   bash stage_modules.sh <output_dir> [lgx_dir]
#
# Prerequisites:
#   - .lgx files built (nix build in each module repo)
#   - basecamp built (for capability_module + logos_host)
set -euo pipefail

die() { echo "FATAL: $*" >&2; exit 1; }

OUTDIR="${1:?Usage: stage_modules.sh <output_dir> [lgx_dir]}"
LGX_DIR="${2:-}"

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  PLATFORM="darwin-arm64-dev"; EXT="dylib";;
    Linux-x86_64)  PLATFORM="linux-x86_64-dev"; EXT="so";;
    Linux-aarch64) PLATFORM="linux-aarch64-dev"; EXT="so";;
    *) die "Unsupported platform: $(uname -s)-$(uname -m)";;
esac

install_lgx() {
    local mdir="$1" lgx="$2"
    local name
    name=$(tar xzOf "$lgx" manifest.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')
    [ -z "$name" ] && die "install_lgx: cannot read name from $lgx"

    local tmp; tmp=$(mktemp -d)
    tar xzf "$lgx" -C "$tmp"

    rm -rf "$mdir/$name"
    mkdir -p "$mdir/$name"
    cp "$tmp/manifest.json" "$mdir/$name/"

    if [ -d "$tmp/variants/$PLATFORM" ]; then
        cp -L "$tmp"/variants/"$PLATFORM"/* "$mdir/$name/"
    else
        die "install_lgx: $PLATFORM variant missing in $lgx"
    fi

    printf '%s' "$PLATFORM" > "$mdir/$name/variant"
    rm -rf "$tmp"
    echo "  Staged: $name"
}

install_extra_lib() {
    local mdir="$1" module="$2" lib="$3"
    [ -f "$lib" ] || die "install_extra_lib: missing $lib for $module"
    cp -L "$lib" "$mdir/$module/"
    echo "  Override: $(basename "$lib") → $module/"
}

resign() {
    if [ "$(uname -s)" = "Darwin" ]; then
        codesign --force --sign - "$1" 2>/dev/null || true
    fi
}

# ─── Create output structure ───
MODULES="$OUTDIR/modules"
mkdir -p "$MODULES"

# ─── Stage capability_module from basecamp ───
echo "=== Staging capability_module ==="
BASECAMP_MODULES=""
for candidate in \
    "$(dirname "$(which logoscore 2>/dev/null || true)")/../modules" \
    /nix/store/*-logos-basecamp-*/modules; do
    [ -d "$candidate/capability_module" ] 2>/dev/null && BASECAMP_MODULES="$candidate" && break
done
if [ -n "$BASECAMP_MODULES" ]; then
    cp -r "$BASECAMP_MODULES/capability_module" "$MODULES/"
    echo "  Staged: capability_module (from basecamp)"
else
    echo "  WARNING: capability_module not found — host mode may fail"
fi

# ─── Stage .lgx modules ───
if [ -n "$LGX_DIR" ]; then
    echo "=== Staging .lgx modules from $LGX_DIR ==="
    for lgx in "$LGX_DIR"/*.lgx; do
        [ -f "$lgx" ] && install_lgx "$MODULES" "$lgx"
    done
fi

# ─── Phase 0.3 dylib overrides ───
echo "=== Applying dylib overrides ==="

# liblogosdelivery.dylib — 17-symbol build
DELIVERY_LIB=$(find /nix/store -name "liblogosdelivery.$EXT" -path '*module-lib*' 2>/dev/null | head -1)
if [ -n "$DELIVERY_LIB" ] && [ -d "$MODULES/delivery_module" ]; then
    install_extra_lib "$MODULES" delivery_module "$DELIVERY_LIB"
    resign "$MODULES/delivery_module/liblogosdelivery.$EXT"
fi

# liblogoschat.dylib — 48MB sim-runtime version
CHAT_LIB=$(find /nix/store -name "liblogoschat.$EXT" -path '*chat-module-lib*' 2>/dev/null | head -1)
if [ -z "$CHAT_LIB" ]; then
    # Fallback: look in sim build output
    CHAT_LIB=$(find /Users/arseniy/Waku/Logos/logos-chat/build -name "liblogoschat.$EXT" 2>/dev/null | head -1)
fi
if [ -n "$CHAT_LIB" ] && [ -d "$MODULES/chat_module" ]; then
    install_extra_lib "$MODULES" chat_module "$CHAT_LIB"
    resign "$MODULES/chat_module/liblogoschat.$EXT"
fi

# ─── Stage logos_host next to monitor binary ───
echo "=== Locating logos_host ==="
LOGOS_HOST=""
for candidate in \
    "$(dirname "$(which logoscore 2>/dev/null || true)")/logos_host" \
    /nix/store/*-logos-basecamp-*/bin/logos_host; do
    [ -x "$candidate" ] 2>/dev/null && LOGOS_HOST="$candidate" && break
done
if [ -n "$LOGOS_HOST" ]; then
    mkdir -p "$OUTDIR/bin"
    cp -L "$LOGOS_HOST" "$OUTDIR/bin/"
    resign "$OUTDIR/bin/logos_host"
    echo "  logos_host → $OUTDIR/bin/"
else
    echo "  WARNING: logos_host not found — host mode may fail"
fi

echo "=== Done. Modules staged at: $MODULES ==="
echo "Launch monitor with:"
echo "  LOGOS_USER_DIR=$OUTDIR ./build/sim-monitor --host-chat --state-dir .sim_state"
