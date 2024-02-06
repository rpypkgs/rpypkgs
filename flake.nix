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
        pypySrc = pkgs.fetchFromGitHub {
          owner = "pypy";
          repo = "pypy";
          rev = "1fca5847f1902f76523d805ed291763b23733ccb";
          sha256 = "sha256-hKZ0KRY6cT4C/7boiBqtv28WjhAcVABuiqtJRsFNHDk=";
        };
        bf = pkgs.stdenv.mkDerivation {
          pname = "bf";
          version = "5";

          src = pkgs.fetchFromGitHub {
            owner = "MG-K";
            repo = "pypy-tutorial-ko";
            rev = "20dd2e807014c75b53d6ed152fe38cb7af171301";
            sha256 = "sha256-7YINSBwuEsuPlCW9Euo0Rs/0Nc6z1n+6g+Wtk332fb4=";
          };

          buildInputs = with pkgs; [ pkg-config libffi ];

          buildPhase = ''
            cp -r ${pypySrc}/{rpython,py} .
            chmod -R u+w rpython/

            sed -i -e 's_, pytest__' rpython/conftest.py
            sed -i -e '/hookimpl/d' rpython/conftest.py

            ${pkgs.pypy2}/bin/pypy rpython/bin/rpython -Ojit example5.py
          '';

          installPhase = ''
            mkdir -p $out/bin/
            cp example5-c $out/bin/bf

            mkdir -p $out/share/
            cp *.b $out/share/
          '';
        };
      in {
        packages = {
          inherit bf;
          inherit (pkgs) pypy2 pypy27 pypy3 pypy38 pypy39;
          typhon = typhon.packages.${system}.typhonVm;
        };
        devShells.default = pkgs.mkShell {
          packages = [];
        };
      }
    );
}
