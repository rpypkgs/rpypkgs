{
  description = "Packages built with RPython";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; }; in
      {
        packages = rec {
          inherit (pkgs) pypy2 pypy27 pypy3 pypy39 pypy310;
        };
        devShells.default = pkgs.mkShell {
          packages = [];
        };
      }
    );
}
