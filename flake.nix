{
  description = "klausur — exam paper distributor NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      systems = lib.systems.flakeExposed;

      # only the files the build needs, so papers and .jj stay out of the store
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

      # module with the server injected, papers still come from ./assets
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

          # node_modules for editors and tsc, without bun install
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
