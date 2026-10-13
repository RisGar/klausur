{
  description = "klausur — exam paper distributor NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, ... }:
    {
      nixosModules.default = ./default.nix;
      nixosModules.klausur = self.nixosModules.default;
    };
}
