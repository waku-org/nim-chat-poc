#!/usr/bin/env bash
# Fix duplicate symbols between librln_mix and rust-bundle on macOS.
set -uo pipefail

LIB="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
RUST_BUNDLE="${2:-}"
[ -n "$RUST_BUNDLE" ] && RUST_BUNDLE="$(cd "$(dirname "$RUST_BUNDLE")" && pwd)/$(basename "$RUST_BUNDLE")"

case "$(uname -s)" in
  Darwin)
    [ -z "$RUST_BUNDLE" ] && echo "Usage: $0 <mix-lib> <rust-bundle-lib>" && exit 0

    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT

    # Match all global symbols (T=text, D=data, S=common, B=BSS, etc — uppercase = global)
    (nm "$RUST_BUNDLE" 2>/dev/null || true) | grep " [TDSBCR] " | awk '{print $3}' | sort -u > "$WORK/b.txt"
    (nm "$LIB" 2>/dev/null || true) | grep " [TDSBCR] " | awk '{print $3}' | sort -u > "$WORK/m.txt"
    comm -12 "$WORK/b.txt" "$WORK/m.txt" > "$WORK/d.txt"
    DCOUNT=$(wc -l < "$WORK/d.txt" | tr -d ' ')
    [ "$DCOUNT" -eq 0 ] && echo "No duplicates." && exit 0
    echo "Localizing $DCOUNT duplicate symbols in $(basename "$LIB")..."

    mkdir "$WORK/o" && cd "$WORK/o"
    ar x "$LIB"
    FIXED=0
    for f in *.o; do
      # Get this object's global text symbols, intersect with dupes
      (nm "$f" 2>/dev/null || true) | grep " [TDSBCR] " | awk '{print $3}' | sort -u > "$WORK/obj.txt"
      comm -12 "$WORK/d.txt" "$WORK/obj.txt" > "$WORK/obj_dupes.txt"
      if [ -s "$WORK/obj_dupes.txt" ]; then
        nmedit -R "$WORK/obj_dupes.txt" "$f"
        FIXED=$((FIXED + 1))
      fi
    done
    rm "$LIB"
    ar rcs "$LIB" *.o
    echo "Fixed $FIXED objects."
    ;;
  *) echo "No fix needed on $(uname -s)" ;;
esac
