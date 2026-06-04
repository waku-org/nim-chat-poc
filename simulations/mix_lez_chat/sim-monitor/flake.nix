{
  description = "Simulation Monitor — Qt/QML desktop app with optional chat host mode";

  inputs = {
    # Use logos-module-builder as Qt source to match liblogos_core's Qt version.
    # This avoids the Qt 6.11 vs 6.9 mismatch that causes logos_core_start() to block.
    logos-module-builder.url = "github:logos-co/logos-module-builder/tutorial-v3";

    # logos-liblogos for host mode headers (LogosAPI, LogosAPIClient)
    logos-liblogos = {
      url = "github:logos-co/logos-liblogos/94af58c819038e0eb5c2003f69d3260d964aa8f3";
    };
  };

  outputs = { self, logos-module-builder, logos-liblogos }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: builtins.listToAttrs (map (s: { name = s; value = f s; }) systems);

      # Get nixpkgs from logos-module-builder (same Qt as basecamp/liblogos_core)
      nixpkgsFor = system: logos-module-builder.inputs.logos-nix.inputs.nixpkgs.legacyPackages.${system};
    in {
      packages = forAll (system:
        let pkgs = nixpkgsFor system;
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
          pkgs = nixpkgsFor system;
          liblogosInclude = logos-liblogos.packages.${system}.logos-liblogos-include;
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
              export LIBLOGOS_INCLUDE="${liblogosInclude}/include"
              # For host mode: link against basecamp's liblogos_core (same Qt version)
              export BASECAMP_LIB="/nix/store/5qry4yw3zf6vg7xbck0xgk9rw7wyf322-logos-basecamp-0.0.0-dev/lib"
              echo "sim-monitor dev shell (Qt $(${pkgs.qt6.qtbase}/bin/qtpaths6 --qt-version 2>/dev/null || echo 6.9.x))"
              echo "  cmake -B build -GNinja [-DENABLE_HOST_MODE=ON] && cmake --build build"
            '';
          };
        });
    };
}
