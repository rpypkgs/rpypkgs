{ fetchFromGitHub, fetchPypi, writeShellScript }:
let
  # Simple setup hook: at the end of patchPhase, unpack a RPython library
  # into the build directory, next to rpython/, so that it can be
  # imported during buildPhase.
  mkUnpackHook = name: action: writeShellScript "unpack-${name}" ''
    ${name}UnpackRPythonLib() {
      ${action}
    }
    postPatchHooks+=(${name}UnpackRPythonLib)
  '';


  appdirsSrc = fetchFromGitHub {
    owner = "ActiveState";
    repo = "appdirs";
    rev = "1.4.4";
    sha256 = "sha256-6hODshnyKp2zWAu/uaWTrlqje4Git34DNgEGFxb8EDU=";
  };
  macropySrc = fetchFromGitHub {
    owner = "lihaoyi";
    repo = "macropy";
    rev = "13993ccb08df21a0d63b091dbaae50b9dbb3fe3e";
    sha256 = "12496896c823h0849vnslbdgmn6z9mhfkckqa8sb8k9qqab7pyyl";
  };
  pycparserSrc = fetchPypi {
    pname = "pycparser";
    version = "2.21";
    sha256 = "sha256-5kT97BL3hy+GxY/3kNpFYhixD4Y5cCSVFtYKXqyncgY=";
  };
  rplySrc = fetchFromGitHub {
    owner = "rpypkgs";
    repo = "rply";
    rev = "5cfe4daeb8feb6d0fae268212c884d369eac634e";
    sha256 = "sha256-0G/jbEQrC5sqJ9mQylC0eaBQSweXS49DPdSfQRHQWRM=";
  };
  rsdlSrc = fetchPypi {
    pname = "rsdl";
    version = "0.4.2";
    sha256 = "sha256-SWApgO/lRMUOfx7wCJ6F6EezpNrzbh4CHCMI7y/Gi6U=";
  };
in {
  appdirs = mkUnpackHook "appdirs" ''
    cp ${appdirsSrc}/appdirs.py .
  '';
  macropy = mkUnpackHook "macropy" ''
    cp -r ${macropySrc}/macropy/ .
  '';
  pycparser = mkUnpackHook "pycparser" ''
    tar -k -zxf ${pycparserSrc}
    mv pycparser-2.21/pycparser/ .
  '';
  rply = mkUnpackHook "rply" ''
    cp -r ${rplySrc}/rply/ .
  '';
  rsdl = mkUnpackHook "rsdl" ''
    tar -k -zxf ${rsdlSrc}
    mv rsdl-0.4.2/rsdl/ .
  '';
}
