# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  net = impurifier.makeNetPackage { pkg = pkgs.hello; };
  offline = impurifier.makeOfflinePackage { pkg = pkgs.hello; };
  closure = pkgs.closureInfo {
    rootPaths = [
      net
      offline
    ];
  };
in
{
  unit = impurifier.unit;
  emitter =
    pkgs.runCommand "pacman-impurifier-contract"
      {
        nativeBuildInputs = [
          pkgs.pacman
          pkgs.libarchive
        ];
      }
      ''
        bsdtar -xOf ${net} .PKGINFO | grep '^pkgname = hello-net$'
        bsdtar -xOf ${
          impurifier.makeRuntimePackage { nixDependency = "my-nix-runtime"; }
        } .PKGINFO | grep '^depend = my-nix-runtime$'
        test "$(wc -l < ${closure}/store-paths)" = 2
        touch $out
      '';
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
