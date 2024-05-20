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
        # TODO elm-live src/Main.elm --hot --start-page index.html --pushstate -- --output=elm.js
        devenv.shells.default = {
          packages = [
            pkgs.elmPackages.elm-live
            pkgs.nodePackages.http-server
          ];
          languages.elm.enable = true;

          scripts.build-frontend.exec = ''
            mkdir dist
            elm make src/Main.elm --output dist/elm.js --optimize
            cp index.html dist
            cp -r assets dist
            cp *.js dist
            cp manifest.json dist
          '';

          scripts.dev-frontend.exec = ''
            ${pkgs.pkgs.elmPackages.elm-live}/bin/elm-live src/Main.elm -s index.html -u true -- --output elm.js
          '';

          processes = {
            frontend.exec = "dev-frontend";
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
