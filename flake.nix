{
  description = "Description for the project";

  inputs = {
    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    devenv.url = "github:cachix/devenv";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = inputs@{ flake-parts, devenv-root, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      perSystem = { config, self', inputs', pkgs, system, ... }: {
        packages.${system}.default = pkgs.runCommand "" {} '''';
        devenv.shells.default = {
          languages.elm.enable = true;
          # languages.rust.enable = true;

          packages = [
            pkgs.fermyon-spin
          ];

          scripts.dev-web.exec = ''
            cd $(git rev-parse --show-toplevel)
            cd apps/web
            ${pkgs.elmPackages.elm-live}/bin/elm-live src/Main.elm -d public -s index.html -u true -x /api -y http://127.0.0.1:3000/api -- --output public/elm.js
          '';

          scripts.dev-backend.exec = ''
            cd $(git rev-parse --show-toplevel)
            cd apps
            ${pkgs.fermyon-spin}/bin/spin watch
          '';

          scripts.dev-all.exec = ''
            dev-web & dev-backend
          '';

          processes = {
            web.exec = "dev-web";
            backend.exec = "dev-backend";
          };
        };

      };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
