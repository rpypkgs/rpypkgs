{
  description = "Packages built with RPython";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # RPython's list of supported systems: https://www.pypy.org/features.html
      # Tested systems have had at least one package built and manually
      # confirmed to work; they do not need to support every interpreter. ~ C.
      testedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      untestedSystems = [
        "i686-linux" "i686-windows" "i686-freebsd13" "i686-openbsd"
        "x86_64-darwin" "x86_64-freebsd13" "x86_64-openbsd"
        "armv6l-linux" "armv7l-linux"
        "aarch64-darwin"
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

        # Bootstrap CPython 2.7 for compiling PyPy for Python 2.7
        cpython2 = pkgs.callPackage ./bootstrap/default.nix {
          sourceVersion = {
            major = "2";
            minor = "7";
            patch = "18";
            suffix = ".8"; # ActiveState's Python 2 extended support
          };
          hash = "sha256-HUOzu3uJbtd+3GbmGD35KOk/CDlwL4S7hi9jJGRFiqI=";
          inherit (pkgs.darwin) configd;
          reproducibleBuild = true;
          rebuildBytecode = false;
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

        macropySrc = pkgs.fetchFromGitHub {
          owner = "lihaoyi";
          repo = "macropy";
          rev = "13993ccb08df21a0d63b091dbaae50b9dbb3fe3e";
          sha256 = "12496896c823h0849vnslbdgmn6z9mhfkckqa8sb8k9qqab7pyyl";
        };
        macropy = mkUnpackHook "macropy" ''
          cp -r ${macropySrc}/macropy/ .
        '';

        pycparserSrc = pkgs.fetchPypi {
          pname = "pycparser";
          version = "2.21";
          sha256 = "sha256-5kT97BL3hy+GxY/3kNpFYhixD4Y5cCSVFtYKXqyncgY=";
        };
        pycparser = mkUnpackHook "pycparser" ''
          tar -k -zxf ${pycparserSrc}
          mv pycparser-2.21/pycparser/ .
        '';

        mkRPythonDerivation = {
          entrypoint, binName,
          nativeBuildInputs ? [], buildInputs ? [],
          optLevel ? "jit",
          binInstallName ? binName,
          py2 ? "${pkgs.pypy2}/bin/pypy",
          transFlags ? "",
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

            ${py2} rpython/bin/rpython -O${optLevel} ${entrypoint} ${transFlags}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin/
            cp ${binName} $out/bin/${binInstallName}

            runHook postInstall
          '';
        } // attrs);
        pypy2 = mkRPythonDerivation {
          entrypoint = "pypy/goal/targetpypystandalone.py";
          binName = "pypy-c";
          optLevel = "2";
          nativeBuildInputs = [ pycparser ];
          transFlags = "--translationmodules";
          # buildInputs = with pkgs; [ bzip2 expat gdbm ncurses openssl sqlite xz zlib ];
          buildInputs = with pkgs; [ ncurses zlib ];
          py2 = "${cpython2}/bin/python";
        } {
          pname = "pypy2";
          version = "7.3.15";

          src = pypySrc;

          # PyPy has a hardcoded stdlib search routine, so the tree has to look
          # something like this, including symlinks.
          postInstall = ''
            mkdir -p $out/pypy-c/
            cp -R {include,lib_pypy,lib-python} $out/pypy-c/
            mv $out/bin/pypy-c $out/pypy-c/
            ln -s $out/pypy-c/pypy-c $out/bin/pypy

            mkdir -p $out/lib/
            cp libpypy-c${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/
            ln -s $out/pypy-c/lib-python/2.7 $out/lib/pypy2.7

            mkdir -p $out/include/
            ln -s $out/pypy-c/include $out/include/pypy2.7
          '';
        };
        divspl = mkRPythonDerivation {
          entrypoint = "divspl.py";
          binName = "divspl-c";
          binInstallName = "divspl";
        } {
          pname = "divspl";
          version = "1";

          src = ./divspl;

          doCheck = true;
          checkPhase = "./divspl-c fizzbuzz.divspl";

          postInstall = ''
            mkdir -p $out/share/
            cp *.divspl $out/share/
          '';
        };
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
        pyrolog = mkRPythonDerivation {
          entrypoint = "targetprologstandalone.py";
          binName = "pyrolog-c";
          binInstallName = "pyrolog";
        } {
          pname = "pyrolog";
          version = "2013";

          src = pkgs.fetchFromGitHub {
            owner = "cosmoharrigan";
            repo = "pyrolog";
            rev = "b250e3ec0109049dea09419f2ad6a8ed14d92ff0";
            sha256 = "sha256-GBhh83f0FI33Bba2tIAo9HbveTlgczQINBHqMZ5a2sA=";
          };

          meta = {
            description = "A Prolog interpreter written in Python using the PyPy translator toolchain";
            license = pkgs.lib.licenses.mit;
          };
        };
        hippyvm = mkRPythonDerivation {
          entrypoint = "targethippy.py";
          binName = "hippy-c";
          nativeBuildInputs = [ pkgs.mysql-client pkgs.pcre.dev pkgs.rhash pkgs.bzip2.dev rply appdirs ];
        } {
          pname = "hippyvm";
          version = "2015";

          prePatch = ''
            sed -ie 's,from rpython.rlib.rfloat import isnan,from math import isnan,' hippy/objects/*.py
          '';

          src = pkgs.fetchFromGitHub {
            owner = "hippyvm";
            repo = "hippyvm";
            rev = "2ae35b80023dbc4f0735e1388528d28ed7b234fd";
            sha256 = "sha256-0aIJTpFdk86HSwDXZyP5ahfyuMcMfljoSrvsceYX4i0=";
          };

          meta = {
            description = "an implementation of the PHP language in RPython";
            license = pkgs.lib.licenses.mit;
          };
        };
      in {
        lib = {
          inherit mkUnpackHook mkRPythonDerivation;
        };
        packages = {
          inherit (pkgs) pypy2 pypy27 pypy3 pypy38 pypy39;
          inherit bf divspl hippyvm topaz pygirl pysom pyrolog;
          # Testing only!
          bootpy = pypy2;
          # XXX need to rescope these instead of statically providing them here
          # nix is angy that this isn't a derivation
          rpythonPackages = {
            inherit appdirs macropy pycparser rply rsdl;
          };
        };
        devShells.default = pkgs.mkShell {
          packages = builtins.filter (p: !p.meta.broken) (with pkgs; [
            cachix nix-tree
          ]);
        };
      }
    );
}
