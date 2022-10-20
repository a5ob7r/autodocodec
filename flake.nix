{
  description = "autodocodec";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-22.05";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    gitignore.url = "github:hercules-ci/gitignore.nix";
    validity.url = "github:NorfairKing/validity";
    validity.flake = false;
    safe-coloured-text.url = "github:NorfairKing/safe-coloured-text";
    safe-coloured-text.flake = false;
    sydtest.url = "github:NorfairKing/sydtest";
    sydtest.flake = false;
    nixpkgs-22_05.url = "github:NixOS/nixpkgs?ref=nixos-22.05";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-22_05
    , flake-utils
    , pre-commit-hooks
    , gitignore
    , validity
    , safe-coloured-text
    , sydtest
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ]
      (system:
      let
        pkgsFor = nixpkgs: import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.${system}
            (import (validity + "/nix/overlay.nix"))
            (import (safe-coloured-text + "/nix/overlay.nix"))
            (import (sydtest + "/nix/overlay.nix"))
            (final: previous: { inherit (import gitignore { inherit (final) lib; }) gitignoreSource; })
          ];
        };
        pkgs = pkgsFor nixpkgs;
      in
      {
        overlays = final: prev:
          with final.haskell.lib;
          {

            haskellPackages = prev.haskellPackages.override (old: {
              overrides = final.lib.composeExtensions (old.overrides or (_: _: { }))
                (
                  self: super:
                    let
                      autodocodecPkg = name:
                        buildFromSdist (overrideCabal (self.callPackage (./${name}/default.nix) { }) (old: {
                          doBenchmark = true;
                          configureFlags = (old.configureFlags or [ ]) ++ [
                            # Optimisations
                            "--ghc-options=-O2"
                            # Extra warnings
                            "--ghc-options=-Wall"
                            "--ghc-options=-Wincomplete-uni-patterns"
                            "--ghc-options=-Wincomplete-record-updates"
                            "--ghc-options=-Wpartial-fields"
                            "--ghc-options=-Widentities"
                            "--ghc-options=-Wredundant-constraints"
                            "--ghc-options=-Wcpp-undef"
                            "--ghc-options=-Werror"
                            "--ghc-options=-Wno-deprecations"
                          ];
                          # Ugly hack because we can't just add flags to the 'test' invocation.
                          # Show test output as we go, instead of all at once afterwards.
                          testTarget = (old.testTarget or "") + " --show-details=direct";
                        }));

                      autodocodecPackages =
                        final.lib.genAttrs [
                          "autodocodec"
                          "autodocodec-api-usage"
                          "autodocodec-openapi3"
                          "autodocodec-schema"
                          "autodocodec-servant-multipart"
                          "autodocodec-swagger2"
                          "autodocodec-yaml"
                        ]
                          autodocodecPkg;
                    in
                    {
                      inherit autodocodecPackages;

                      autodocodecRelease =
                        final.symlinkJoin {
                          name = "autodocodec-release";
                          paths = final.lib.attrValues self.autodocodecPackages;
                        };
                    } // autodocodecPackages
                );
            });
          };

        packages.release = pkgs.haskellPackages.autodocodecRelease;
        packages.default = self.packages.${system}.release;
        checks =
          let
            backwardCompatibilityCheckFor = nixpkgs:
              let pkgs' = pkgsFor nixpkgs;
              in pkgs'.haskellPackages.autodocodecRelease;
            allNixpkgs = {
              inherit
                nixpkgs-22_05;
            };
            backwardCompatibilityChecks = pkgs.lib.mapAttrs (_: nixpkgs: backwardCompatibilityCheckFor nixpkgs) allNixpkgs;
          in
          backwardCompatibilityChecks // {
            pre-commit = pre-commit-hooks.lib.${system}.run {
              src = ./.;
              hooks = {
                hlint.enable = true;
                hpack.enable = true;
                ormolu.enable = true;
                nixpkgs-fmt.enable = true;
                nixpkgs-fmt.excludes = [ ".*/default.nix" ];
                cabal2nix.enable = true;
              };
            };
          };
        devShells.default = pkgs.haskellPackages.shellFor {
          name = "autodocodec-shell";
          packages = (p:
            (builtins.attrValues p.autodocodecPackages)
          );
          withHoogle = true;
          doBenchmark = true;
          buildInputs = with pkgs; [
            niv
            zlib
            cabal-install
          ] ++ (with pre-commit-hooks;
            [
              hlint
              hpack
              nixpkgs-fmt
              ormolu
              cabal2nix
            ]);
          shellHook = self.checks.${system}.pre-commit.shellHook;
        };
      });
}
