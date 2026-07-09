{ lib, stdenv, nim, which, pkg-config, writeScriptBin, fetchurl,
  openssl, miniupnpc, libnatpmp, rustPlatform, fetchFromGitHub, darwin ? {},
  src,         # logos-chat source (self from flake, with submodules=1)
  nwakuDeps,   # nim deps from vendor/nwaku/nix/deps.nix (logos-delivery pin)
  rustBundleDrv }:  # result of rust_bundle.nix

# NOTE: this build requires git submodules to be present in src.
# When fetching from GitHub use '?submodules=1#', e.g.:
#   nix build "github:logos-messaging/logos-chat?submodules=1#"
# For local builds use: nix build ".?submodules=1#"

assert lib.assertMsg ((src.submodules or false) == true)
  "Unable to build without submodules. Append '?submodules=1#' to the URI.";

let
  revision = lib.substring 0 8 (src.rev or "dirty");

  # nwaku (logos-delivery pin) nim deps on the path. Drop `ffi` — the chat ships
  # its own vendor/nim-ffi (1-arg declareLibrary); nwaku's ffi (2-arg) would clash.
  nwakuDepPaths = lib.concatStringsSep " " (builtins.concatMap
    (p: [ "--path:${p}" "--path:${p}/src" ])
    (builtins.attrValues (builtins.removeAttrs nwakuDeps [ "ffi" ])));

  # Mix RLN spam-protection lib. The plugin builds a STATELESS zerokit RLN
  # instance via `ffi_rln_new()` (the full build segfaults there — it expects
  # tree resources the stateless build compiles out). So we use the prebuilt
  # stateless release asset — the same one the local `make` build and the mix sim
  # use — fetched reproducibly by hash.
  #
  # liblogoschat already statically links libchat's rust bundle; embedding librln
  # statically too would put two copies of the Rust runtime in one image and
  # collide on `_rust_eh_personality` / `_ffi_c_string_free`. On darwin we link
  # librln's cdylib (its runtime stays in its own image — no symbol surgery), with
  # an @rpath install name so liblogoschat.dylib loads it from beside itself. On
  # linux we keep the static .a + `-Wl,--allow-multiple-definition`.
  rlnTriplet = {
    aarch64-darwin = "aarch64-apple-darwin";
    x86_64-darwin = "x86_64-apple-darwin";
    x86_64-linux = "x86_64-unknown-linux-gnu";
    aarch64-linux = "aarch64-unknown-linux-gnu";
  }.${stdenv.hostPlatform.system} or (throw "no stateless librln triplet for ${stdenv.hostPlatform.system}");
  rlnHash = {
    aarch64-darwin = "sha256-f2YppkPsKFdN00j+IY8fpvsebWTIb9lW/V1/vOTiVKU=";
    x86_64-darwin = "sha256-ZaHP5CApN66FYY7jxwOmGcF9kJR78Fng3k1qE2W08Mk=";
    x86_64-linux = "sha256-qbrUdaetYKFhjzxUP/QcwD3JHWJ8qk/tCMK3yXceIAk=";
    aarch64-linux = "sha256-s4bWrmCcNTWHNyJwV73ilWNp58ZdAVG+TAgtWN1cTQs=";
  }.${stdenv.hostPlatform.system} or (throw "add stateless librln hash for ${stdenv.hostPlatform.system}");
  rlnTarball = fetchurl {
    url = "https://github.com/vacp2p/zerokit/releases/download/v2.0.2/${rlnTriplet}-stateless-rln.tar.gz";
    hash = rlnHash;
  };
  mixRlnDylib = stdenv.mkDerivation {
    name = "librln-mix-stateless-v2.0.2";
    dontUnpack = true;
    buildPhase = ''
      mkdir -p $out/lib
      tar -xzf ${rlnTarball}
      cp release/librln.* $out/lib/
      chmod +w $out/lib/*
    '' + lib.optionalString stdenv.isDarwin ''
      install_name_tool -id @rpath/librln.dylib $out/lib/librln.dylib
    '';
    dontInstall = true;
  };
in stdenv.mkDerivation {
  pname = "liblogoschat";
  version = "0.1.0";
  inherit src;

  NIMFLAGS = (lib.concatStringsSep " " ([
    "--passL:${rustBundleDrv}/lib/liblogoschat_rust_bundle.a"
    "--passL:-lm"
    "-d:miniupnpcUseSystemLibs"
    "-d:libnatpmpUseSystemLibs"
    "--passL:-lminiupnpc"
    "--passL:-lnatpmp"
    "-d:git_version=${revision}"
    "-d:libp2p_mix_experimental_exit_is_dest"
  ] ++ lib.optionals stdenv.isDarwin [
    # link librln via its cdylib so its Rust runtime stays in its own image
    "--passL:-L${mixRlnDylib}/lib"
    "--passL:-lrln"
    "--passL:-Wl,-rpath,@loader_path"
  ] ++ lib.optionals stdenv.isLinux [
    "--passL:${mixRlnDylib}/lib/librln.a"
    "--passL:-Wl,--allow-multiple-definition"
  ])) + " " + nwakuDepPaths;

  nativeBuildInputs = let
    fakeGit = writeScriptBin "git" ''
      #!${stdenv.shell}
      echo "${revision}"
    '';
  in [ nim which pkg-config fakeGit ];

  # Nim defaults to $HOME/.cache/nim; the sandbox maps $HOME to /homeless-shelter
  # which doesn't exist. Point XDG_CACHE_HOME at /tmp so Nim writes its cache there.
  XDG_CACHE_HOME = "/tmp";

  buildInputs = [ openssl miniupnpc libnatpmp ];

  configurePhase = ''
    runHook preConfigure
    patchShebangs . vendor/nimbus-build-system > /dev/null 2>&1 || true
    # Create logos_chat.nims symlink (if not already a real file)
    if [ ! -e logos_chat.nims ]; then
      ln -sf logos_chat.nimble logos_chat.nims
    fi
    # Regenerate nimble-link files with sandbox-correct absolute paths.
    # vendor/.nimble/pkgs contains paths baked in at `nimble develop` time on a
    # developer's machine; they won't resolve inside the Nix sandbox. Running
    # the same generate_nimble_links.sh that logos-delivery uses re-creates them
    # from the current $PWD without requiring git.
    make nimbus-build-system-nimble-dir
    runHook postConfigure
  '';

  preBuild = ''
    mkdir -p build
  '';

  makeFlags = [ "liblogoschat-nix" ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/include
    cp build/liblogoschat.so    $out/lib/ 2>/dev/null || true
    cp build/liblogoschat.dylib $out/lib/ 2>/dev/null || true
    ls $out/lib/liblogoschat.* > /dev/null
    # Ship librln.dylib beside liblogoschat.dylib so its @rpath/@loader_path
    # load command resolves at runtime (darwin only).
    ${lib.optionalString stdenv.isDarwin ''
      cp ${mixRlnDylib}/lib/librln.dylib $out/lib/
    ''}
    cp library/liblogoschat.h   $out/include/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Logos-Chat shared library (C FFI)";
    homepage = "https://github.com/logos-messaging/logos-chat";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
