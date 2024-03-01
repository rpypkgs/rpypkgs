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
    let
      # RPython's list of supported systems: https://www.pypy.org/features.html
      # Tested systems have had at least one package built and manually
      # confirmed to work; they do not need to support every interpreter. ~ C.
      testedSystems = [
        "x86_64-linux"
      ];
      untestedSystems = [
        "i686-linux" "i686-windows" "i686-freebsd13" "i686-openbsd"
        "x86_64-darwin" "x86_64-freebsd13" "x86_64-openbsd"
        "armv6l-linux" "armv7l-linux"
        "aarch64-linux" "aarch64-darwin"
        "powerpc64-linux"
        "powerpc64le-linux"
        "s390x-linux"
      ];
    in flake-utils.lib.eachSystem (testedSystems ++ untestedSystems) (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Required for bootstrapping.
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

        # Simple setup hook: at the end of patchPhase, unpack a RPython library
        # into the build directory, next to rpython/, so that it can be
        # imported during buildPhase.
        mkUnpackHook = name: action: pkgs.writeShellScript "unpack-${name}" ''
          ${name}UnpackRPythonLib() {
            ${action}
          }
          postPatchHooks+=(${name}UnpackRPythonLib)
        '';

        rplySrc = pkgs.fetchFromGitHub {
          owner = "alex";
          repo = "rply";
          rev = "v0.7.8";
          sha256 = "sha256-mO/wcIsDIBjoxUsFvzftj5H5ziJijJcoyrUk52fcyE4=";
        };
        rply = mkUnpackHook "rply" ''
          cp -r ${rplySrc}/rply/ .
        '';

        appdirsSrc = pkgs.fetchFromGitHub {
          owner = "ActiveState";
          repo = "appdirs";
          rev = "1.4.4";
          sha256 = "sha256-6hODshnyKp2zWAu/uaWTrlqje4Git34DNgEGFxb8EDU=";
        };
        appdirs = mkUnpackHook "appdirs" ''
          cp ${appdirsSrc}/appdirs.py .
        '';

        rsdlSrc = pkgs.fetchPypi {
          pname = "rsdl";
          version = "0.4.2";
          sha256 = "sha256-SWApgO/lRMUOfx7wCJ6F6EezpNrzbh4CHCMI7y/Gi6U=";
        };
        rsdl = mkUnpackHook "rsdl" ''
          tar -k -zxf ${rsdlSrc}
          mv rsdl-0.4.2/rsdl/ .
        '';

        mkRPythonDerivation = {
          entrypoint, binName,
          nativeBuildInputs ? [], buildInputs ? [],
          optLevel ? "jit",
          binInstallName ? binName
        }: attrs: pkgs.stdenv.mkDerivation ({
          inherit nativeBuildInputs;
          buildInputs = builtins.concatLists [
            buildInputs (with pkgs; [ pkg-config libffi ])
          ];

          postPatch = ''
            cp -r ${pypySrc}/{rpython,py} .
            chmod -R u+w rpython/

            sed -i -e 's_, pytest__' rpython/conftest.py
            sed -i -e '/hookimpl/d' rpython/conftest.py
          '';

          buildPhase = ''
            runHook preBuild

            # For rply, set XDG cache to someplace writeable.
            export XDG_CACHE_HOME=$TMPDIR

            ${pkgs.pypy2}/bin/pypy rpython/bin/rpython -O${optLevel} ${entrypoint}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin/
            cp ${binName} $out/bin/${binInstallName}

            runHook postInstall
          '';
        } // attrs);
        bf = mkRPythonDerivation {
          entrypoint = "example5.py";
          binName = "example5-c";
          binInstallName = "bf";
        } {
          pname = "bf";
          version = "5";

          src = pkgs.fetchFromGitHub {
            owner = "MG-K";
            repo = "pypy-tutorial-ko";
            rev = "20dd2e807014c75b53d6ed152fe38cb7af171301";
            sha256 = "sha256-7YINSBwuEsuPlCW9Euo0Rs/0Nc6z1n+6g+Wtk332fb4=";
          };

          postInstall = ''
            mkdir -p $out/share/
            cp *.b $out/share/
          '';

          # XXX unknown license; copyright Andrew Brown
        };
        topaz = mkRPythonDerivation {
          entrypoint = "targettopaz.py";
          binName = "bin/topaz";
          nativeBuildInputs = [ pkgs.git appdirs rply ];
        } {
          pname = "topaz";
          version = "2022.6";

          src = pkgs.fetchFromGitHub {
            owner = "topazproject";
            repo = "topaz";
            rev = "059eac0ac884d677c3539e156e0ac528723d6238";
            sha256 = "sha256-3Sx6gfRdM4tXKQjo5fCrL6YoOTObhnNC8PPJgAFTfcg=";
          };

          patches = [ ./topaz.patch ];

          meta = {
            description = "A high performance ruby, written in RPython";
            license = pkgs.lib.licenses.bsd3;
          };
        };
        pygirl = mkRPythonDerivation {
          entrypoint = "pygirl/targetgbimplementation.py";
          binName = "targetgbimplementation-c";
          binInstallName = "pygirl";
          optLevel = "2";
          nativeBuildInputs = [ rsdl ];
          buildInputs = with pkgs; [ SDL SDL2 ];
        } {
          pname = "pygirl";
          version = "16.11";

          src = pkgs.fetchFromGitHub {
            owner = "Yardanico";
            repo = "PyGirlGameboy";
            rev = "674dcbed21d1c2912187c1e234d44990739383b4";
            sha256 = "sha256-YEc7d98LwZpbkp4OV6J2iXWn/z/7RHL0dmnkkEU/agE=";
          };

          # XXX shipped without license, originally same license as PyPy
          meta = {
            description = "GameBoy emulator written in RPython";
            license = pkgs.lib.licenses.mit;
          };
        };
        coreLib = pkgs.fetchFromGitHub {
          owner = "SOM-st";
          repo = "SOM";
          rev = "79f33c8a2376ce25288fe5b382a0e79f8f529472";
          sha256 = "sha256-R8MKNaZgOyZct8BCcK/ILQtyBFLv5PvtyLsrB0Dh5uc=";
        };
        pysom = mkRPythonDerivation {
          entrypoint = "src/main_rpython.py";
          # XXX hardcoded
          binName = "som-ast-jit";
        } {
          pname = "pysom";
          version = "23.10";

          src = pkgs.fetchFromGitHub {
            owner = "SOM-st";
            repo = "PySOM";
            rev = "b7acae57068a02418f334fd84a209ac485ba7b98";
            sha256 = "sha256-OwYVO/o8mXSwntMPZNaGXlrCFp/iZEO5q7Gj4DAq6bY=";
          };

          # XXX could also be "BC"
          SOM_INTERP = "AST";

          doCheck = true;
          checkPhase = ''
            ./som-ast-jit -cp ${coreLib}/Smalltalk ${coreLib}/TestSuite/TestHarness.som
          '';

          postInstall = ''
            mkdir -p $out/share/
            cp -H -r ${coreLib}/{Smalltalk,Examples,TestSuite} $out/share/
          '';

          meta = {
            description = "The Simple Object Machine Smalltalk implemented in Python";
            license = pkgs.lib.licenses.mit;
          };
        };
      in {
        packages = {
          inherit (pkgs) pypy2 pypy27 pypy3 pypy38 pypy39;
          inherit bf topaz pygirl pysom;
          typhon = typhon.packages.${system}.typhonVm;
        };
        devShells.default = pkgs.mkShell {
          packages = [];
        };
      }
    );
}
