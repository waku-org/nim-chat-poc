{
  description = "Simulation Monitor — Qt/QML desktop app with optional chat host mode";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    logos-liblogos = {
      url = "github:logos-co/logos-liblogos/94af58c819038e0eb5c2003f69d3260d964aa8f3";
      inputs.logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk/25c88f4d48fa95ea4437194bcf60bd8d0cf84a74";
    };
  };

  outputs = { self, nixpkgs, logos-liblogos }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAll (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.stdenv.mkDerivation {
            pname = "sim-monitor";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.cmake pkgs.qt6.wrapQtAppsHook ];
            buildInputs = [
              pkgs.qt6.qtbase
              pkgs.qt6.qtdeclarative
            ];
            cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
          };
        });

      devShells = forAll (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          liblogosLib = logos-liblogos.packages.${system}.logos-liblogos-lib;
          liblogosInclude = logos-liblogos.packages.${system}.logos-liblogos-include;
          liblogosBin = logos-liblogos.packages.${system}.logos-liblogos-bin;
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = [ pkgs.qt6.wrapQtAppsHook ];
            packages = [
              pkgs.cmake
              pkgs.ninja
              pkgs.qt6.qtbase
              pkgs.qt6.qtdeclarative
              pkgs.qt6.qtshadertools
              pkgs.qt6.qtremoteobjects
            ];
            shellHook = ''
              export QML2_IMPORT_PATH="${pkgs.qt6.qtdeclarative}/lib/qt-6/qml"
              export LIBLOGOS_LIB="${liblogosLib}/lib"
              export LIBLOGOS_INCLUDE="${liblogosInclude}/include"
              export LOGOS_HOST_BIN="${liblogosBin}/bin/logos_host"
              echo "sim-monitor dev shell"
              echo "  LIBLOGOS_LIB=$LIBLOGOS_LIB"
              echo "  LIBLOGOS_INCLUDE=$LIBLOGOS_INCLUDE"
              echo "  LOGOS_HOST_BIN=$LOGOS_HOST_BIN"
              echo "  cmake -B build -GNinja -DENABLE_HOST_MODE=ON && cmake --build build"
            '';
          };
        });
    };
}
