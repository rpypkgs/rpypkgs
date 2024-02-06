{
  description = "Packages built with RPython";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    typhon = {
      url = "github:monte-language/typhon";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, typhon }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.permittedInsecurePackages = [
            "python-2.7.18.6"
          ];
        };
      in {
        packages = {
          inherit (pkgs) pypy2 pypy27 pypy3 pypy38 pypy39;
          typhon = typhon.packages.${system}.typhonVm;
        };
        devShells.default = pkgs.mkShell {
          packages = [];
        };
      }
    );
}
