# Borrowed from nixpkgs; for some reason .overrideAttrs doesn't work on
# ocamlPackages, so I had to do a textual inclusion. ~ C.
{
  lib,
  fetchFromGitHub,
  buildDunePackage,
  base64,
  omd,
  menhir, menhirLib,
  ott,
  linenoise,
  dune-site,
  pprint,
  makeWrapper,
  lem,
  linksem,
  yojson,
}:

buildDunePackage rec {
  pname = "sail";
  version = "0.18";

  src = fetchFromGitHub {
    owner = "rems-project";
    repo = "sail";
    rev = version;
    sha256 = "sha256-QvVK7KeAvJ/RfJXXYo6xEGEk5iOmVsZbvzW28MHRFic=";
  };

  minimalOCamlVersion = "4.08";

  nativeBuildInputs = [
    makeWrapper
    ott
    menhir
    lem
  ];

  propagatedBuildInputs = [
    base64
    omd
    dune-site
    linenoise
    pprint
    linksem
    yojson
    menhirLib
  ];

  # `buildDunePackage` only builds the [pname] package
  # This doesnt work in this case, as sail includes multiple packages in the same source tree
  buildPhase = ''
    runHook preBuild
    dune build --release ''${enableParallelBuilding:+-j $NIX_BUILD_CORES}
    runHook postBuild
  '';
  checkPhase = ''
    runHook preCheck
    dune runtest ''${enableParallelBuilding:+-j $NIX_BUILD_CORES}
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    dune install --prefix $out --libdir $OCAMLFIND_DESTDIR
    runHook postInstall
  '';
  postInstall = ''
    wrapProgram $out/bin/sail --set SAIL_DIR $out/share/sail
  '';

  meta = with lib; {
    homepage = "https://github.com/rems-project/sail";
    description = "Language for describing the instruction-set architecture (ISA) semantics of processors";
  };
}

