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
        rplySrc = pkgs.fetchFromGitHub {
          owner = "alex";
          repo = "rply";
          rev = "v0.7.8";
          sha256 = "sha256-mO/wcIsDIBjoxUsFvzftj5H5ziJijJcoyrUk52fcyE4=";
        };
        appdirsSrc = pkgs.fetchFromGitHub {
          owner = "ActiveState";
          repo = "appdirs";
          rev = "1.4.4";
          sha256 = "sha256-6hODshnyKp2zWAu/uaWTrlqje4Git34DNgEGFxb8EDU=";
        };
        rsdlSrc = pkgs.fetchPypi {
          pname = "rsdl";
          version = "0.4.2";
          sha256 = "sha256-SWApgO/lRMUOfx7wCJ6F6EezpNrzbh4CHCMI7y/Gi6U=";
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
        topaz = pkgs.stdenv.mkDerivation {
          pname = "topaz";
          version = "2022.6";

          src = pkgs.fetchFromGitHub {
            owner = "topazproject";
            repo = "topaz";
            rev = "059eac0ac884d677c3539e156e0ac528723d6238";
            sha256 = "sha256-3Sx6gfRdM4tXKQjo5fCrL6YoOTObhnNC8PPJgAFTfcg=";
          };

          buildInputs = with pkgs; [ pkg-config libffi git ];

          patches = [ ./topaz.patch ];

          buildPhase = ''
            cp -r ${pypySrc}/{rpython,py,pypy}/ .
            chmod -R u+w rpython/

            sed -i -e 's_, pytest__' rpython/conftest.py
            sed -i -e '/hookimpl/d' rpython/conftest.py

            cp -r ${rplySrc}/rply/ .
            cp ${appdirsSrc}/appdirs.py .

            # For rply, set cache to someplace writeable.
            export XDG_CACHE_HOME=$TMPDIR

            ${pkgs.pypy2}/bin/pypy rpython/bin/rpython -Ojit targettopaz.py
          '';

          installPhase = ''
            mkdir -p $out/bin/
            cp bin/topaz $out/bin/
          '';
        };
        pygirl = pkgs.stdenv.mkDerivation {
          pname = "pygirl";
          version = "16.11";

          src = pkgs.fetchFromGitHub {
            owner = "Yardanico";
            repo = "PyGirlGameboy";
            rev = "674dcbed21d1c2912187c1e234d44990739383b4";
            sha256 = "sha256-YEc7d98LwZpbkp4OV6J2iXWn/z/7RHL0dmnkkEU/agE=";
          };

          buildInputs = with pkgs; [ pkg-config libffi SDL SDL2 ];

          buildPhase = ''
            cp -r ${pypySrc}/{rpython,py,pypy}/ .
            chmod -R u+w rpython/

            sed -i -e 's_, pytest__' rpython/conftest.py
            sed -i -e '/hookimpl/d' rpython/conftest.py

            tar -zxf ${rsdlSrc}
            mv rsdl-0.4.2/rsdl/ .

            ${pkgs.pypy2}/bin/pypy rpython/bin/rpython pygirl/targetgbimplementation.py
          '';

          installPhase = ''
            mkdir -p $out/bin/
            cp targetgbimplementation-c $out/bin/pygirl
          '';
        };
      in {
        packages = {
          inherit (pkgs) pypy2 pypy27 pypy3 pypy38 pypy39;
          inherit bf topaz pygirl;
          typhon = typhon.packages.${system}.typhonVm;
        };
        devShells.default = pkgs.mkShell {
          packages = [];
        };
      }
    );
}
