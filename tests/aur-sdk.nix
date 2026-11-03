# SPDX-License-Identifier: MIT
{ pkgs }:
let
  pyalpm = pkgs.python3Packages.buildPythonPackage {
    pname = "pyalpm";
    version = "0.12.0-unstable-2026-09-06";
    pyproject = true;
    src = pkgs.fetchzip {
      url = "https://github.com/archlinux/pyalpm/archive/e64a1bce65aebcdc0a618d8afa6bec086a97cd16.tar.gz";
      hash = "sha256-xvUpC701hXyBnINb7wKi/RO/qLJ0NnSXqeg0A76NFjk=";
    };
    build-system = [ pkgs.python3Packages.meson-python ];
    nativeBuildInputs = [
      pkgs.pkg-config
      pkgs.python3Packages.pytest
    ];
    buildInputs = [
      pkgs.pacman
      pkgs.libarchive
    ];
    dontUseCmakeConfigure = true;
    dontUseMesonConfigure = true;
    doCheck = false;
    pythonImportsCheck = [
      "pyalpm"
      "pycman.config"
    ];
    meta.license = pkgs.lib.licenses.gpl3Plus;
  };
  pikaur = pkgs.python3Packages.buildPythonApplication {
    pname = "pikaur";
    version = "1.34";
    pyproject = true;
    src = pkgs.fetchzip {
      url = "https://github.com/actionless/pikaur/archive/refs/tags/1.34.tar.gz";
      hash = "sha256-+IwQQ0Okdx9X36jfEXQIduocrKR9dPzmLrTOwYctLiA=";
    };
    build-system = [ pkgs.python3Packages.hatchling ];
    dependencies = [ pyalpm ];
    doCheck = false;
    meta.license = pkgs.lib.licenses.gpl3Only;
  };
  trizen = pkgs.stdenvNoCC.mkDerivation {
    pname = "trizen";
    version = "1.68";
    src = pkgs.fetchzip {
      url = "https://github.com/trizen/trizen/archive/refs/tags/1.68.tar.gz";
      hash = "sha256-0LayEf8WerOuIhAtA4hVxKjWhtcGmvfi6/RyCTzIGdg=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin $out/share/licenses/trizen
      cp LICENSE $out/share/licenses/trizen/
      cp trizen $out/bin/trizen
      chmod +x $out/bin/trizen
      substituteInPlace $out/bin/trizen \
        --replace-fail /usr/bin/perl ${pkgs.perl}/bin/perl \
        --replace-fail /usr/bin/whoami ${pkgs.coreutils}/bin/whoami \
        --replace-fail /usr/bin/uname ${pkgs.coreutils}/bin/uname \
        --replace-fail /usr/bin/sudo /run/wrappers/bin/sudo \
        --replace-fail /usr/bin/pacman ${pkgs.pacman}/bin/pacman \
        --replace-fail /usr/bin/makepkg ${pkgs.pacman}/bin/makepkg
      wrapProgram $out/bin/trizen --prefix PERL5LIB : "${
        pkgs.perlPackages.makePerlPath [
          pkgs.perlPackages.URI
          pkgs.perlPackages.libwwwperl
          pkgs.perlPackages.LogMessage
          pkgs.perlPackages.LogMessageSimple
          pkgs.perlPackages.TermUI
          pkgs.perlPackages.JSON
          pkgs.perlPackages.DataDump
          pkgs.perlPackages.LWPProtocolhttps
          pkgs.perlPackages.TermReadLineGnu
        ]
      }"
    '';
    meta.license = pkgs.lib.licenses.gpl3Plus;
  };

  pacaur = pkgs.stdenvNoCC.mkDerivation {
    pname = "pacaur";
    version = "4.8.6";
    src = pkgs.fetchzip {
      url = "https://github.com/E5ten/pacaur/archive/0b63edae748a21392d671884221ec5a3072bf79a.tar.gz";
      hash = "sha256-Xc91+gH4eviIBPs4Ug7cr5YrJ4ZnxPjDoIMoLu9yoyk=";
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      mkdir -p $out/bin $out/share/licenses/pacaur
      cp LICENSE $out/share/licenses/pacaur/
      cp pacaur $out/bin/pacaur
      chmod +x $out/bin/pacaur
      patchShebangs $out/bin/pacaur
      wrapProgram $out/bin/pacaur --set LIBRARY ${pkgs.pacman}/share/makepkg
    '';
    meta.license = pkgs.lib.licenses.isc;
  };

  aura = pkgs.rustPlatform.buildRustPackage {
    pname = "aura";
    version = "4.2.0";
    src = pkgs.fetchzip {
      url = "https://github.com/fosskers/aura/archive/refs/tags/v4.2.0.tar.gz";
      hash = "sha256-nAwb5u42lyWuLQ3kvJrq876U8YakRplQLlTRjDZrJN4=";
    };
    sourceRoot = "source/rust";
    cargoHash = "sha256-eCuxNkmZInbwspA2W/D49Z9OXuhrPhgggd691Egw2Yc=";
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.pacman
      pkgs.libarchive
      pkgs.curl
      pkgs.openssl
    ];
    doCheck = false;
    postInstall = ''
      mkdir -p $out/share/licenses/aura
      cp ../LICENSE $out/share/licenses/aura/
    '';
    meta.license = pkgs.lib.licenses.gpl3Only;
  };

in
{
  inherit
    pyalpm
    pikaur
    trizen
    pacaur
    aura
    ;
  inherit (import ./pamac-sdk.nix { inherit pkgs; }) pamac;
}
