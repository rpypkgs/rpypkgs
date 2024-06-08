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
      # Bump template/flake.nix when new systems are tested, too.
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
    in {
      templates.default = {
        path = ./template;
        description = "A basic RPython project";
      };
    } // (flake-utils.lib.eachSystem (testedSystems ++ untestedSystems) (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Phase 0: Bootstrap CPython 2.7 for compiling PyPy for Python 2.7.
        cpython2 = pkgs.callPackage ./bootstrap/default.nix {
          sourceVersion = {
            major = "2";
            minor = "7";
            patch = "18";
            suffix = ".8"; # ActiveState's Python 2 extended support
          };
          hash = "sha256-HUOzu3uJbtd+3GbmGD35KOk/CDlwL4S7hi9jJGRFiqI=";
          inherit (pkgs.darwin) configd;
        };

        # Libraries written for RPython.
        libs = pkgs.callPackage ./libs.nix {};

        pypySrc = pkgs.fetchFromGitHub {
          owner = "pypy";
          repo = "pypy";
          rev = "1fca5847f1902f76523d805ed291763b23733ccb";
          sha256 = "sha256-hKZ0KRY6cT4C/7boiBqtv28WjhAcVABuiqtJRsFNHDk=";
        };

        # Generic builder for RPython. Takes three levels of configuration.
        mkRPythonMaker = { py2 }: {
          # The Python module to start at, and the resulting binary name.
          entrypoint, binName,
          # What name to install the binary as.
          binInstallName ? binName,
          # Pure-Python libraries to be "installed" for Python 2.7 prior to
          # translation. See libs.nix for available libraries.
          withLibs ? (ls: []),
          # Whether to build a JIT, as well as some other optimizations.
          # Usually should be "jit" (JIT on) or "2" (JIT off).
          optLevel ? "jit",
          # Extra flags for the translator, e.g. to enable stackless.
          transFlags ? "",
          # Extra flags for the interpreter, e.g. to enable builtin modules.
          interpFlags ? "",
          # Whether translation depends on anything from PyPy's source code
          # (pypy.*) which isn't available in RPython (rpython.*) or Py (py.*).
          # The latter packages are always available.
          usesPyPyCode ? false,
        }: attrs: let
          buildInputs = builtins.concatLists [
            (attrs.buildInputs or [])
            ([ pkgs.libffi ])
            (pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ libunwind Security ]))
          ];
        in pkgs.stdenv.mkDerivation (attrs // {
          # Ensure that RPython binaries don't have Python runtime dependencies.
          # disallowedReferences = [ py2 ];
          # To that end, don't automatically add references to Python modules!
          # dontPatchShebangs = true;

          inherit buildInputs;
          nativeBuildInputs = builtins.concatLists [
            (attrs.nativeBuildInputs or [])
            (withLibs libs)
            ([ pkgs.pkg-config ])
          ];

          # Set up library search paths for translation.
          C_INCLUDE_PATH = pkgs.lib.makeSearchPathOutput "dev" "include" buildInputs;
          LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath
            (builtins.filter (x : x.outPath != pkgs.stdenv.cc.libc.outPath or "") buildInputs);

          # conftest patches are required to build without pytest.
          # sre patches are required to build without pypy/ src.
          postPatch = ''
            cp -r ${pypySrc}/{rpython,py} .
            ${pkgs.lib.optionalString usesPyPyCode "cp -r ${pypySrc}/pypy ."}
            chmod -R u+w rpython/

            sed -i -e 's_, pytest__' rpython/conftest.py
            sed -i -e '/hookimpl/d' rpython/conftest.py

            sed -i -e 's,raise ImportError,pass;,' rpython/rlib/rsre/rsre_constants.py
          '';

          # https://github.com/pypy/pypy/blob/main/rpython/translator/goal/translate.py
          # For rply, set XDG cache to someplace writeable.
          # Don't run debugger on failure.
          # Use as many cores as Nix tells us to use.
          buildPhase = ''
            runHook preBuild

            export XDG_CACHE_HOME=$TMPDIR

            ${py2} rpython/bin/rpython \
              --batch \
              --make-jobs="$NIX_BUILD_CORES" \
              -O${optLevel} \
              ${transFlags} \
              ${entrypoint} ${interpFlags}

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin/
            cp ${binName} $out/bin/${binInstallName}

            runHook postInstall
          '';
        });

        # Phase 1: Build PyPy for Python 2.7 using CPython.
        mkRPythonBootstrap = mkRPythonMaker {
          py2 = "${cpython2}/bin/python";
        };
        mkPyPy = import ./make-pypy.nix;
        pypy2Minimal = mkPyPy {
          inherit pkgs;
          rpyMaker = mkRPythonBootstrap;
          pyVersion = "2.7";
          version = "7.3.15";
          binName = "pypy-c";
          minimal = true;
          src = pypySrc;
        };

        # Phase 2: Build everything else using PyPy.
        mkRPythonDerivation = mkRPythonMaker {
          py2 = "${pypy2Minimal}/bin/pypy";
        };

        pypy2 = mkPyPy {
          inherit pkgs;
          rpyMaker = mkRPythonDerivation;
          pyVersion = "2.7";
          version = "7.3.15";
          binName = "pypy-c";
          src = pypySrc;
        };
        pypy3 = mkPyPy rec {
          inherit pkgs;
          rpyMaker = mkRPythonDerivation;
          binName = "pypy3-c";
          pyVersion = "3.10";
          version = "7.3.15";
          src = pkgs.fetchurl {
            url = "https://downloads.python.org/pypy/pypy3.10-v${version}-src.tar.bz2";
            hash = "sha256-g3YiEws2YDoYk4mb2fUplhqOSlbJ62cmjXLd+JIMlXk=";
          };
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
        bfShare = pkgs.fetchFromGitHub {
          owner = "MG-K";
          repo = "pypy-tutorial-ko";
          rev = "20dd2e807014c75b53d6ed152fe38cb7af171301";
          sha256 = "sha256-7YINSBwuEsuPlCW9Euo0Rs/0Nc6z1n+6g+Wtk332fb4=";
        };
        bf = mkRPythonDerivation {
          entrypoint = "bf.py";
          binName = "bf-c";
          binInstallName = "bf";
        } {
          pname = "bf";
          version = "2024";

          src = ./bf;

          postInstall = ''
            mkdir -p $out/share/
            cp ${bfShare}/*.b $out/share/
          '';

          meta = {
            description = "Brainfuck interpreter written in RPython";
            license = pkgs.lib.licenses.mit;
          };
        };
        pixie = mkRPythonDerivation {
          entrypoint = "target.py";
          binName = "pixie-vm";
          optLevel = "2";
          transFlags = "--continuation";
        } {
          pname = "pixie";
          version = "2017";

          src = pkgs.fetchFromGitHub {
            owner = "pixie-lang";
            repo = "pixie";
            rev = "d76adb041a4968906bf22575fee7a572596e5796";
            sha256 = "sha256-NO3S1p1NI28Jq4D8+n8ZYK4KZTltN8m1r8CZ91JjAtM=";
          };

          # Force a newer Unicode DB.
          # Patch out old FFI code.
          prePatch = ''
            sed -ie 's,6_2_0,9_0_0,g' pixie/vm/libs/string.py
            sed -ie '/@as_var(u"pixie.ffi", u"ffi-prep-callback")/d' pixie/vm/libs/ffi.py
          '';

          meta = {
            broken = true;
            description = "A small fast native Lisp with 'magical' powers";
            license = pkgs.lib.licenses.gpl3;
          };
        };
        topaz = mkRPythonDerivation {
          entrypoint = "targettopaz.py";
          binName = "bin/topaz";
          withLibs = ls: [ ls.appdirs ls.rply ];
          usesPyPyCode = true;
        } {
          pname = "topaz";
          version = "2022.6";

          src = pkgs.fetchFromGitHub {
            owner = "topazproject";
            repo = "topaz";
            rev = "059eac0ac884d677c3539e156e0ac528723d6238";
            sha256 = "sha256-3Sx6gfRdM4tXKQjo5fCrL6YoOTObhnNC8PPJgAFTfcg=";
          };

          nativeBuildInputs = [ pkgs.git ];

          patches = [ ./topaz.patch ];

          meta = {
            broken = true;
            description = "A high performance ruby, written in RPython";
            license = pkgs.lib.licenses.bsd3;
          };
        };
        pygirl = mkRPythonDerivation {
          entrypoint = "pygirl/targetgbimplementation.py";
          binName = "targetgbimplementation-c";
          binInstallName = "pygirl";
          optLevel = "2";
          withLibs = ls: [ ls.rsdl ];
        } {
          pname = "pygirl";
          version = "16.11";

          src = pkgs.fetchFromGitHub {
            owner = "Yardanico";
            repo = "PyGirlGameboy";
            rev = "674dcbed21d1c2912187c1e234d44990739383b4";
            sha256 = "sha256-YEc7d98LwZpbkp4OV6J2iXWn/z/7RHL0dmnkkEU/agE=";
          };

          buildInputs = with pkgs; [ SDL SDL2 ];

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
          withLibs = ls: [ ls.appdirs ls.rply ];
        } {
          pname = "hippyvm";
          version = "2015";

          src = pkgs.fetchFromGitHub {
            owner = "hippyvm";
            repo = "hippyvm";
            rev = "2ae35b80023dbc4f0735e1388528d28ed7b234fd";
            sha256 = "sha256-0aIJTpFdk86HSwDXZyP5ahfyuMcMfljoSrvsceYX4i0=";
          };

          nativeBuildInputs = with pkgs; [ mysql-client pcre.dev rhash bzip2.dev ];

          prePatch = ''
            sed -ie 's,from rpython.rlib.rfloat import isnan,from math import isnan,' hippy/objects/*.py
          '';

          meta = {
            description = "an implementation of the PHP language in RPython";
            license = pkgs.lib.licenses.mit;
          };
        };
      in {
        checks = { inherit divspl; };
        lib = { inherit mkRPythonDerivation; };
        packages = {
          inherit bf divspl hippyvm pixie pygirl pypy2 pypy3 pysom pyrolog topaz;
          # Export bootstrap PyPy. It is just as fast as standard PyPy, but
          # missing some parts of the stdlib.
          inherit pypy2Minimal;
        };
        devShells.default = pkgs.mkShell {
          packages = builtins.filter (p: !p.meta.broken) (with pkgs; [
            cachix nix-tree
            # pypy2Minimal
          ]);
        };
      }
    ));
}
