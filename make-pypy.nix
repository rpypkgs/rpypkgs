{ pkgs, rpyMaker,
  src, pyVersion, version, binName,
  minimal ? false }:
let
  py3k = !(binName == "pypy-c");
in rpyMaker {
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
        --replace "os.environ.get('TIX_LIBRARY')" "'${pkgs.tclPackages.tix}/lib'"
    fi
  '';
  patches = [
    ./pypy/dont_fetch_vendored_deps.patch

    (pkgs.replaceVars ./pypy/tk_tcl_paths.patch {
      inherit (pkgs) tk tcl;
      tk_dev = pkgs.tk.dev;
      tcl_dev = pkgs.tcl;
      tk_libprefix = pkgs.tk.libPrefix;
      tcl_libprefix = pkgs.tcl.libPrefix;
    })

    # https://github.com/NixOS/nixpkgs/issues/419942
    (pkgs.replaceVars (if py3k then ./pypy/sqlite_paths.patch else ./pypy/sqlite_paths_2_7.patch) {
      inherit (pkgs.sqlite) out dev;
      libsqlite = "${pkgs.sqlite.out}/lib/libsqlite3${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
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
    cp *${pkgs.stdenv.hostPlatform.extensions.sharedLibrary} $out/lib/
    if [[ -d $out/pypy-c/lib-python/${pyVersion} ]]; then
      ln -s $out/pypy-c/lib-python/${pyVersion} $out/lib/pypy${pyVersion}
    fi

    mkdir -p $out/include/
    ln -s $out/pypy-c/include $out/include/pypy${pyVersion}
  '';

  # Verify that cffi correctly found various system libraries.
  doInstallCheck = false; # !minimal;
  installCheckPhase = let
    modules = if py3k then [
      "Tkinter" "curses" "sqlite3"
    ] else [
      "curses" "lzma" "sqlite3" "tkinter"
    ];
    modlist = builtins.concatStringsSep ", " modules;
    imports = builtins.concatStringsSep "; " (builtins.map (x: "import ${x}") modules);
    in ''
      echo "Testing whether we can import modules: ${modlist}"
      $out/bin/pypy -c '${imports}'
    '';

  meta.mainProgram = "pypy";
}
