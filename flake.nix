{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        with pkgs;
        {
          devShells.default = mkShell {
            buildInputs = [
              elmPackages.elm
              elmPackages.elm-format
              # elmPackages.elm-review
              elmPackages.lamdera

              elmPackages.elm-language-server
            ];
          };
        }
      );
}

