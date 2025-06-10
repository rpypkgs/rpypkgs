{
  description = "Packages built with RPython";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
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
            suffix = ".11"; # ActiveState's Python 2 extended support
          };
          hash = "sha256-HUpPjDxlkrZrs1E7IFZYAbGKF7sRq5UOPmjTp2MDe0Q=";
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
        mkRPythonMaker = { py2 }: let
          maker = {
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
            dontPatchShebangs = true;

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
              ${pkgs.lib.optionalString usesPyPyCode "cp -r ${pypySrc}/dotviewer ${pypySrc}/pypy ${pypySrc}/lib-python ."}
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
        in maker;

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
          pyVersion = "3.10";
          version = "7.3.15";
          binName = "pypy3.10-c";
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

          postInstall = ''
            mkdir -p $out/share/
            cp *.divspl $out/share/
          '';

          doInstallCheck = true;
          installCheckPhase = "$out/bin/divspl $out/share/fizzbuzz.divspl";
        };
        icbink = mkRPythonDerivation {
          entrypoint = "entry_point.py";
          binName = "entry_point-c";
          binInstallName = "icbink";
        } {
          pname = "icbink";
          version = "2015";

          src = pkgs.fetchFromGitHub {
            owner = "euccastro";
            repo = "icbink";
            rev = "4f3505560eed0dfd737b4c650e1d419dd15d0e12";
            sha256 = "sha256-oHXBbTARik3uIKrdPg7MJ8LLRFnfC7XpXSgwp0A6tVk=";
          };

          postInstall = ''
            mkdir -p $out/share/
            cp *.k $out/share/
          '';
        };
        r1brc = mkRPythonDerivation {
          entrypoint = "1brc.py";
          binName = "1brc-c";
          binInstallName = "1brc";
          optLevel = "2";
        } {
          pname = "1brc";
          version = "1";

          src = ./1brc;
        };
        biia = mkRPythonDerivation {
          entrypoint = "biia.py";
          binName = "biia-c";
          binInstallName = "biia";
          optLevel = "2";
        } {
          pname = "biia";
          version = "1";

          src = ./biia;
        };
        bfShare = pkgs.fetchFromGitHub {
          owner = "cwfitzgerald";
          repo = "brainfuck-benchmark";
          rev = "2e10658581ce0c81b02e858e292984cf8e5df96a";
          sha256 = "sha256-S5RR1CcWzQs+LshHH4DDc24g5z9/YFz/BGd5jOJqjOo=";
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
            cp ${bfShare}/benches/*.b $out/share/
          '';

          meta = {
            description = "Brainfuck interpreter written in RPython";
            license = pkgs.lib.licenses.mit;
          };
        };
        dcpu16py = mkRPythonDerivation {
          entrypoint = "dcpu16.py";
          binName = "dcpu16-c";
          binInstallName = "dcpu16";
          optLevel = "2";
        } {
          pname = "dcpu16py";
          version = "2012";

          src = pkgs.fetchFromGitHub {
            owner = "AlekSi";
            repo = "dcpu16py";
            rev = "721f08af29d5b3d62161a4e1eca9c81801d13619";
            sha256 = "sha256-5uxkIrk8Ae6E6fO5q5w/mIT02J6UrrhTTIEDkDRDlWc=";
          };

          meta = {
            description = "A Python implementation of Notch's DCPU-16 (complete with assembler, disassembler, debugger and video terminal implementations)";
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
            description = "A small fast native Lisp with 'magical' powers";
            license = pkgs.lib.licenses.gpl3;
          };
        };
        plang = mkRPythonDerivation {
          entrypoint = "plang.py";
          binName = "plang-c";
          optLevel = "2";
          withLibs = ls: [ ls.appdirs ls.rply ];
        } {
          pname = "plang";
          version = "2014";

          src = pkgs.fetchFromGitHub {
            owner = "marianoguerra";
            repo = "plang";
            rev = "ba8db7710e1219144e335660b83d106b42ddbdbd";
            sha256 = "sha256-DroIq4geewZ/yhAT0WK6zZppsMEApPHALXYDYwvADyo=";
          };
        };
        pycket = mkRPythonDerivation {
          entrypoint = "targetpycket.py";
          binName = "pycket-c";
          binInstallName = "pycket";
          interpFlags = "--linklets";
          usesPyPyCode = true;
        } {
          pname = "pycket";
          version = "2021";

          src = pkgs.fetchFromGitHub {
            owner = "pycket";
            repo = "pycket";
            rev = "05ebd9885efa3a0ae54e77c1a1f07ea441b445c6";
            sha256 = "sha256-cm349FIzOhtgJwrZVECojLxVUJE4s7sHBXxRCTct320=";
          };

          # Force a newer Unicode DB.
          prePatch = ''
            sed -ie 's,6_2_0,9_0_0,g' pycket/values_string.py pycket/prims/string.py
          '';
        };
        pydgin = mkRPythonDerivation {
          entrypoint = "arm/arm-sim.py";
          binName = "pydgin-arm-nojit";
          binInstallName = "pydgin-arm-nojit";
          optLevel = "2";
        } {
          pname = "pydgin";
          version = "2016";

          src = pkgs.fetchFromGitHub {
            owner = "cornell-brg";
            repo = "pydgin";
            rev = "30f8efa914f26dbee622ebd14d4345840a69c10c";
            sha256 = "sha256-60ZU+1AirK+PFmZz3bigJvS1ATJ+K4ZVhj2zSplc4Cs=";
          };

          meta = {
            description = "A (Py)thon (D)SL for (G)enerating (In)struction set simulators.";
            license = pkgs.lib.licenses.bsd3;
          };
        };
        rsqueak = mkRPythonDerivation {
          entrypoint = "targetrsqueak.py";
          binName = "rsqueak";
          withLibs = ls: [ ls.rsdl ];
        } {
          pname = "rsqueak";
          version = "2023";

          src = pkgs.fetchFromGitHub {
            owner = "hpi-swa";
            repo = "RSqueak";
            rev = "6c2120b38c9d89bf6742508e6a23a6f42df0a0a0";
            sha256 = "sha256-2K9Fzc/IKIU66oerRxqgymYJimSRl9TtjlYMFeKDpas=";
          };

          buildInputs = with pkgs; [ SDL SDL2 ];

          meta = {
            description = "A Squeak/Smalltalk VM written in RPython";
            license = pkgs.lib.licenses.bsd3;
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
            description = "A high performance ruby, written in RPython";
            license = pkgs.lib.licenses.bsd3;
          };
        };
        coreLib = pkgs.fetchFromGitHub {
          owner = "SOM-st";
          repo = "SOM";
          rev = "79f33c8a2376ce25288fe5b382a0e79f8f529472";
          sha256 = "sha256-R8MKNaZgOyZct8BCcK/ILQtyBFLv5PvtyLsrB0Dh5uc=";
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

        # Packages with multiple build-time configurations.
        mkPysom = flavor: let
          SOM_INTERP = pkgs.lib.toUpper flavor;
          # XXX hardcoded for JIT
          binName = "som-${flavor}-jit";
        in mkRPythonDerivation {
          entrypoint = "src/main_rpython.py";
          inherit binName;
        } {
          pname = "pysom";
          version = "23.10";

          src = pkgs.fetchFromGitHub {
            owner = "SOM-st";
            repo = "PySOM";
            rev = "b7acae57068a02418f334fd84a209ac485ba7b98";
            sha256 = "sha256-OwYVO/o8mXSwntMPZNaGXlrCFp/iZEO5q7Gj4DAq6bY=";
          };

          inherit SOM_INTERP;

          postInstall = ''
            mkdir -p $out/share/
            cp -H -r ${coreLib}/{Smalltalk,Examples,TestSuite} $out/share/
          '';

          doInstallCheck = true;
          installCheckPhase = ''
            $out/bin/${binName} -cp $out/share/Smalltalk $out/share/TestSuite/TestHarness.som
          '';

          meta = {
            description = "The Simple Object Machine Smalltalk implemented in Python";
            license = pkgs.lib.licenses.mit;
          };
        };
        pysom-ast = mkPysom "ast";
        pysom-bc = mkPysom "bc";

        sail = pkgs.ocamlPackages.callPackage ./sail.nix {};
        isla-sail = pkgs.ocamlPackages.buildDunePackage rec {
          pname = "sail_isla_backend";
          version = "2024";

          src = pkgs.fetchFromGitHub {
            owner = "rems-project";
            repo = "isla";
            rev = "72e0045d68412f04bff3947a03fe515b84ca1301";
            sha256 = "sha256-FW7LOgiqtHyMZ84aKeVOtc2ai7KQ6S+yiCFCjRRye7Q=";
          };
          sourceRoot = "${src.name}/isla-sail";

          buildInputs = [ pkgs.makeWrapper pkgs.ocamlPackages.base64 sail ];

          postInstall = ''
            mkdir -p $out/bin/
            makeWrapper ${sail}/bin/sail $out/bin/isla-sail --add-flags \
              "--plugin $out/share/libsail/plugins/sail_plugin_isla.cmxs --isla --verbose 1"
          '';
        };
        sail-arm = pkgs.stdenv.mkDerivation rec {
          name = "sail-arm";
          version = "9.4a";

          src = pkgs.fetchFromGitHub {
            owner = "pydrofoil";
            repo = "sail-arm";
            rev = "d43f3f4c021fad07564f6b1e5bc9bd7de33abe4f";
            sha256 = "sha256-Ha4+KKWZ/7h7m2aPAos0F0X1hk/xUduN8EzrXbquHZE=";
          };
          sourceRoot = "${src.name}/arm-v9.4-a";

          nativeBuildInputs = [ isla-sail ];
          buildPhase = "make gen_ir";
          installPhase = ''
            mkdir -p $out/share/
            cp -r ir/ $out/share/
          '';
        };
        sail-riscv = pkgs.fetchFromGitHub {
          owner = "riscv";
          repo = "sail-riscv";
          rev = "b48b40e461f336df3afeb904d1f3c5324f4cd722";
          sha256 = "sha256-7PZNNUMaCZEBf0lOCqkquewRgZPooBOjIbGF7JlLnEo=";
        };
        mkPydrofoil = arch: mkRPythonDerivation {
          entrypoint = "${arch}/target${arch}.py";
          binName = "target${arch}-c";
          binInstallName = "pydrofoil-${arch}";
          optLevel = "2";
          usesPyPyCode = true;
          withLibs = ls: [ ls.appdirs ls.rply ];
        } {
          pname = "pydrofoil-${arch}";
          version = "2025.1.7";

          src = pkgs.fetchFromGitHub {
            owner = "pydrofoil";
            repo = "pydrofoil";
            rev = "ba40be733a5a8e64ba7b7ac1f819f570ab5744ef";
            sha256 = "sha256-l2/csT4qeJ372rD3Xni5+H+S3hPjYqMuLFaSvQAGvEU=";
          };

          buildInputs = [ isla-sail ];

          preBuild = ''
            make pydrofoil/softfloat/SoftFloat-3e/build/Linux-RISCV-GCC/softfloat.o
            # cp ${sail-arm}/share/ir/armv9.ir arm/
          '';

          doInstallCheck = arch == "riscv";
          installCheckPhase = "$out/bin/pydrofoil-${arch} ${sail-riscv}/test/riscv-tests/rv64ui-p-beq.elf";

          meta = {
            description = "A fast RISC-V emulator based on the RISC-V Sail model, and an experimental ARM one";
            license = pkgs.lib.licenses.mit;
          };
        };
        pydrofoil-arm = mkPydrofoil "arm";
        pydrofoil-cheriot = mkPydrofoil "cheriot";
        pydrofoil-riscv = mkPydrofoil "riscv";
      in {
        checks = {
          inherit divspl pysom-ast pysom-bc pypy2 pypy3;
          # XXX need to bump all the intermediate hashes
          # inherit pydrofoil-riscv;
        };
        lib = { inherit mkRPythonDerivation; };
        packages = rec {
          inherit r1brc biia bf dcpu16py divspl hippyvm icbink pixie plang
            pycket pydgin pypy2 pypy3 pyrolog rsqueak topaz;
          inherit pydrofoil-arm pydrofoil-cheriot pydrofoil-riscv;
          inherit pysom-ast pysom-bc;
          # Export bootstrap PyPy. It is just as fast as standard PyPy, but
          # missing some parts of the stdlib.
          inherit pypy2Minimal;
          pysom = pysom-bc;
        };
        devShells.default = pkgs.mkShell {
          packages = builtins.filter (p: !p.meta.broken) (with pkgs; [
            cachix nix-tree
            # pypy2Minimal
            # linuxPackages.perf gdb
          ]);
        };
      }
    ));
}
