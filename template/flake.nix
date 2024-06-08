{
  description = "Packages built with RPython";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
    flake-utils.url = "github:numtide/flake-utils";
    rpypkgs = {
      url = "github:rpypkgs/rpypkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, flake-utils, rpypkgs }:
    let
      # The systems where RPython has been tested to work.
      testedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in flake-utils.lib.eachSystem testedSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        interp = rpypkgs.lib.${system}.mkRPythonDerivation {
          # The Python 2.7 module containing the entrypoint.
          entrypoint = "main.py";
          # The name of the binary after translation.
          binName = "main-c";
          # The desired name of the binary in $out/bin/.
          binInstallName = "interp";
          # Uncomment if the interpreter doesn't have a JIT.
          # optLevel = "2";
          # Any support libraries required for translation.
          withLibs = ls: [];
        } {
          # The package name and version.
          pname = "interp";
          version = "2024";

          # The base directory for the translation.
          src = ./interp;

          meta = {
            description = "An interpreter written in RPython";
            license = pkgs.lib.licenses.mit;
          };
        };
      in {
        packages.default = interp;
      }
    );
}
