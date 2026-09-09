# Forked from pkgs/stdenv/linux/stdenv-bootstrap-tools.nix
{
  lib,
  stdenv,
  libc,
  libffi,
  ncurses,
  nukeReferences,
  pypy,
  runCommand,
  zlib,
}:
stdenv.mkDerivation (finalAttrs: {
  name = "minimal-pypy-bootstrap";

  nativeBuildInputs = [ nukeReferences ];

  buildCommand = ''
    set -x
    mkdir -p $out/bin $out/lib

    # Copy what we need of Glibc.
    cp -d ${libc.out}/lib/ld*.so* $out/lib
    cp -d ${libc.out}/lib/libc*.so* $out/lib
    cp -d ${libc.out}/lib/libdl*.so* $out/lib
    cp -d ${libc.out}/lib/libm*.so* $out/lib
    cp -d ${libc.out}/lib/libpthread*.so* $out/lib
    cp -d ${libc.out}/lib/librt*.so*  $out/lib
    cp -d ${libc.out}/lib/libutil*.so* $out/lib

    chmod -R u+w "$out"
    # libc can contain linker scripts: find them, copy their deps,
    # and get rid of absolute paths (nuke-refs would make them useless)
    local lScripts=$(grep --files-with-matches --max-count=1 'GNU ld script' -R "$out/lib")
    cp -d -t "$out/lib/" $(cat $lScripts | tr " " "\n" | grep -F '${libc.out}' | sort -u)
    for f in $lScripts; do
      substituteInPlace "$f" --replace '${libc.out}/lib/' ""
    done

    cp -d ${pypy.out}/bin/pypy $out/bin
    cp -d ${pypy.out}/lib/libpypy-c.so $out/lib
    cp -dR ${pypy.out}/pypy-c/ $out/pypy-c

    cp -d ${libffi.out}/lib/libffi.so* $out/lib
    cp -d ${ncurses.out}/lib/libncursesw.so* $out/lib
    cp -d ${zlib.out}/lib/libz.so* $out/lib

    chmod -R u+w $out

    # Strip executables even further.
    for i in $out/bin/*; do
        if test -x $i -a ! -L $i; then
            chmod +w $i
            $STRIP -s $i || true
        fi
    done

    nuke-refs $out/pypy-c/pypy-c
    nuke-refs $out/lib/*

    mkdir $out/.pack
    mv $out/* $out/.pack
    mv $out/.pack $out/pack

    mkdir $out/on-server
    XZ_OPT="-9 -e" tar cvJf $out/on-server/pypy-bootstrap.tar.xz --hard-dereference --sort=name --numeric-owner --owner=0 --group=0 --mtime=@1 -C $out/pack .
  ''; # */

  # The result should not contain any references (store paths) so
  # that we can safely copy them out of the store and to other
  # locations in the store.
  allowedReferences = [];

  passthru.bootstrapFiles.bootstrapTools =
    runCommand "pypy-bootstrap.tar.xz" { }
      "cp ${finalAttrs.finalPackage}/on-server/pypy-bootstrap.tar.xz $out";
})
