{ pkgs, rpyMaker,
  src, pyVersion, version, binName,
  minimal ? false }:
rpyMaker {
  inherit binName;
  entrypoint = "pypy/goal/targetpypystandalone.py";
  optLevel = "jit";
  withLibs = ls: [ ls.pycparser ];
  interpFlags = if minimal then "--translationmodules --withmod-thread" else "--allworkingmodules";
} {
  pname = if minimal then "pypy-${pyVersion}-minimal" else "pypy-${pyVersion}";

  inherit version src;
  buildInputs = with pkgs; [
    ncurses zlib
  ] ++ lib.optionals (!minimal) (with pkgs; [
    bzip2 expat gdbm openssl sqlite tcl tk xz
  ]);

  prePatch = ''
    substituteInPlace lib_pypy/pypy_tools/build_cffi_imports.py \
      --replace "multiprocessing.cpu_count()" "$NIX_BUILD_CORES"

    if [[ -f lib-python/3/tkinter/tix.py ]]; then
      substituteInPlace lib-python/3/tkinter/tix.py \
        --replace "os.environ.get('TIX_LIBRARY')" "'${pkgs.tix}/lib'"
    fi
  '';
  patches = [
    ./pypy/dont_fetch_vendored_deps.patch

    (pkgs.substituteAll {
      src = ./pypy/tk_tcl_paths.patch;
      inherit (pkgs) tk tcl;
      tk_dev = pkgs.tk.dev;
      tcl_dev = pkgs.tcl;
      tk_libprefix = pkgs.tk.libPrefix;
      tcl_libprefix = pkgs.tcl.libPrefix;
    })

    (pkgs.substituteAll {
      src = ./pypy/sqlite_paths.patch;
      inherit (pkgs.sqlite) out dev;
    })
  ];

  # PyPy has a hardcoded stdlib search routine, so the tree has to look
  # something like this, including symlinks.
  postInstall = ''
    mkdir -p $out/pypy-c/
    cp -R {include,lib_pypy,lib-python} $out/pypy-c/
    mv $out/bin/${binName} $out/pypy-c/
    ln -s $out/pypy-c/${binName} $out/bin/pypy

    mkdir -p $out/lib/
    cp libpypy-c${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/
    ln -s $out/pypy-c/lib-python/${pyVersion} $out/lib/pypy${pyVersion}

    mkdir -p $out/include/
    ln -s $out/pypy-c/include $out/include/pypy${pyVersion}
  '';

  # Verify that cffi correctly found various system libraries.
  doInstallCheck = !minimal;
  installCheckPhase = let
    modules = if (binName == "pypy3-c") then [
      "curses" "lzma" "sqlite3" "tkinter"
    ] else [
      "Tkinter" "curses" "sqlite3"
    ];
    modlist = builtins.concatStringsSep ", " modules;
    imports = builtins.concatStringsSep "; " (builtins.map (x: "import ${x}") modules);
    in ''
      echo "Testing whether we can import modules: ${modlist}"
      $out/bin/pypy -c '${imports}'
    '';
}
