# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  artifact = impurifier.makeOfflinePackage { pkg = pkgs.hello; };
  runtime = impurifier.makePkgbuild { package = impurifier.runtimePackage; };
  remote = impurifier.makePkgbuild {
    package = artifact;
    sourceUrl = "https://mirror.example.org/native/hello.pkg.tar.zst";
  };
  bundle = impurifier.makePkgbuild { package = artifact; };
in
pkgs.runCommand "pacman-impurifier-pkgbuild-contract" { nativeBuildInputs = [ pkgs.bash ]; } ''
  cd ${bundle}
  bash -n PKGBUILD
  bash -c 'source PKGBUILD; test "$pkgname" = hello-offline; test "$pkgver" = ${pkgs.hello.version}; test "$(sha256sum impurifier.pkg.tar.zst | cut -d" " -f1)" = "''${sha256sums[0]}"; [[ "''${depends[*]}" == *pacman-impurifier* ]]'
  test ! -e ${remote}/impurifier.pkg.tar.zst
  grep -F "https://mirror.example.org/native/hello.pkg.tar.zst" ${remote}/PKGBUILD
  bash -n ${runtime}/impurifier.install
  grep -F install=impurifier.install ${runtime}/PKGBUILD
  touch $out
''
