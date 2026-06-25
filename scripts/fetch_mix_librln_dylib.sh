#!/usr/bin/env bash
# Stage the mix-RLN shared library (librln.dylib / librln.so) for the host
# platform.
#
# liblogoschat also statically links libchat's Rust bundle; linking librln
# statically too puts two copies of the Rust runtime in one image and collides
# at link time (`_rust_eh_personality`, `_ffi_c_string_free`). Consuming librln
# as a cdylib keeps its runtime in its own image — nothing collides and no
# symbol surgery is needed. We pull the prebuilt shared lib from zerokit's
# stateless release (the same asset build_rln.sh uses for the static archive)
# and give it an @rpath install name so liblogoschat.dylib loads it from beside
# itself at runtime.
set -euo pipefail

out="${1:?usage: fetch_mix_librln_dylib.sh <out-path> [rln-version]}"
rln_version="${2:-v2.0.2}"

case "$(uname -s)" in
  Darwin) ext="dylib" ;;
  *)      ext="so" ;;
esac

# Host target triple, e.g. aarch64-apple-darwin / x86_64-unknown-linux-gnu.
host_triplet="$(rustc --version --verbose | awk '/host:/{print $2}')"
tarball="${host_triplet}-stateless-rln.tar.gz"
url="https://github.com/vacp2p/zerokit/releases/download/${rln_version}/${tarball}"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

echo "Fetching mix RLN shared lib: ${url}"
curl --silent --fail-with-body -L "${url}" -o "${work}/${tarball}"
tar -xzf "${work}/${tarball}" -C "${work}"

mkdir -p "$(dirname "${out}")"
cp "${work}/release/librln.${ext}" "${out}"
chmod +w "${out}"

# Repoint the install name to @rpath so the consuming library finds it via its
# own @loader_path (we ship librln.dylib beside liblogoschat.dylib).
if [ "${ext}" = "dylib" ]; then
  install_name_tool -id "@rpath/$(basename "${out}")" "${out}"
fi

echo "Staged $(basename "${out}") at ${out}"
