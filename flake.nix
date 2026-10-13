{
  description = "klausur — exam paper distributor NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = lib.systems.flakeExposed;

      # exactly the files the build needs: the papers, .jj and any lingering
      # node_modules must not be copied into the store
      src = nixpkgs.lib.fileset.toSource {
        root = ./.;
        fileset = nixpkgs.lib.fileset.unions [
          ./index.ts
          ./package.json
          ./tsconfig.json
        ];
      };

      # the compiled server, built with whichever nixpkgs asks for it
      klausur = pkgs: pkgs.callPackage ./default.nix { inherit src; };

      # node_modules with only the type packages, pinned by hash (see types.nix)
      nodeModules = pkgs: pkgs.callPackage ./types.nix { };

      typecheck =
        pkgs:
        pkgs.callPackage ./typecheck.nix {
          inherit src;
          nodeModules = nodeModules pkgs;
        };

      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # the module with the server injected, so `services.klausur.package` has
      # a default while the papers keep coming from ./assets
      module = { pkgs, ... }@args: import ./module.nix (args // { klausurPackage = klausur pkgs; });
    in
    {
      packages = forAll (pkgs: {
        default = klausur pkgs;
        klausur = klausur pkgs;
      });

      checks = forAll (pkgs: {
        default = klausur pkgs;
        typecheck = typecheck pkgs;
      });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.bun
            pkgs.typescript
          ];

          # editors and `tsc` find the types immediately; no `bun install`
          shellHook = ''
            ln -sfn ${nodeModules pkgs}/node_modules node_modules
          '';
        };
      });

      nixosModules = {
        default = module;
        klausur = module;
      };
    };
}
