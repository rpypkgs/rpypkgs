{ pkgs, rpyMaker,
  src, pyVersion, version, binName,
  minimal ? false }:
rpyMaker {
  inherit binName;
  entrypoint = "pypy/goal/targetpypystandalone.py";
  optLevel = "jit";
  withLibs = ls: [ ls.pycparser ];
  interpFlags = pkgs.lib.optionalString minimal "--translationmodules";
} {
  pname = if minimal then "pypy-${pyVersion}-minimal" else "pypy-${pyVersion}";

  inherit version src;
  buildInputs = with pkgs; [
    ncurses zlib
  ] ++ lib.optionals (!minimal) (with pkgs; [
    bzip2 expat gdbm openssl sqlite xz
  ]);

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
}
