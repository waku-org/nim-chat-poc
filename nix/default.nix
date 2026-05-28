{ lib, stdenv, nim, which, pkg-config, writeScriptBin,
  openssl, miniupnpc, libnatpmp, rustPlatform, fetchFromGitHub, darwin ? {},
  src,         # logos-chat source (self from flake, with submodules=1)
  rustBundleDrv }:  # result of rust_bundle.nix

# NOTE: this build requires git submodules to be present in src.
# When fetching from GitHub use '?submodules=1#', e.g.:
#   nix build "github:logos-messaging/logos-chat?submodules=1#"
# For local builds use: nix build ".?submodules=1#"

assert lib.assertMsg ((src.submodules or false) == true)
  "Unable to build without submodules. Append '?submodules=1#' to the URI.";

let
  revision = lib.substring 0 8 (src.rev or "dirty");
  logosChatSrc = src;

  zerokitMixSrc = fetchFromGitHub {
    owner = "vacp2p";
    repo = "zerokit";
    rev = "v2.0.0";
    hash = "sha256-5a2cL26uw7NdLCD0gCA3tS7uX8W9yxRGqcPhWNevstM=";
  };

  mixRlnLib = rustPlatform.buildRustPackage {
    pname = "librln-mix";
    version = "2.0.0";
    src = zerokitMixSrc;
    cargoHash = "sha256-SoMl0QBBgTG1b4UhOlErlzWmg3J6G0xOC0tNDddOptA=";
    buildAndTestSubdir = "rln";
    buildType = "release";
    nativeBuildInputs = lib.optionals stdenv.isDarwin [ darwin.cctools ];
    doCheck = false;
    installPhase = ''
      mkdir -p $out/lib
      find target -name "librln.a" -exec cp {} $out/lib/librln_mix_v2.0.0.a \;
      ls $out/lib/librln_mix_v2.0.0.a
    '' + lib.optionalString stdenv.isDarwin ''
      bash ${logosChatSrc}/scripts/fix_mix_librln_dupes.sh $out/lib/librln_mix_v2.0.0.a ${rustBundleDrv}/lib/liblogoschat_rust_bundle.a
    '';
  };
in stdenv.mkDerivation {
  pname = "liblogoschat";
  version = "0.1.0";
  inherit src;

  NIMFLAGS = lib.concatStringsSep " " ([
    "--passL:${rustBundleDrv}/lib/liblogoschat_rust_bundle.a"
    "--passL:${mixRlnLib}/lib/librln_mix_v2.0.0.a"
    "--passL:-lm"
    "-d:miniupnpcUseSystemLibs"
    "-d:libnatpmpUseSystemLibs"
    "--passL:-lminiupnpc"
    "--passL:-lnatpmp"
    "-d:git_version=${revision}"
    "-d:libp2p_mix_experimental_exit_is_dest"
  ] ++ lib.optionals stdenv.isLinux [
    "--passL:-Wl,--allow-multiple-definition"
  ]);

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
