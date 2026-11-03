# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  tool =
    name: version:
    pkgs.runCommand "${name}-${version}"
      {
        pname = name;
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${name}-${version}\n' > $out/bin/${name}
        chmod +x $out/bin/${name}
      '';
  config = pkgs.writeText "native-pacman.conf" ''
    [options]
    Architecture = x86_64
    SigLevel = Never
  '';
  command = "pacman --root /srv/target --dbpath /srv/target/var/lib/pacman --config ${config} --noconfirm";
  install = "${command} -U /tmp/packages/*.pkg.tar.zst\n${command} -D --asdeps $(${command} -Qq | grep '^nix-store-')";
in
import (coreSrc + "/tests/native-vm.nix") {
  inherit pkgs install;
  name = "alpm";
  tools = [ pkgs.pacman ];
  first = impurifier.makeNativePackages { pkg = tool "native-first" "1"; };
  second = impurifier.makeNativePackages { pkg = tool "native-second" "1"; };
  upgraded = impurifier.makeNativePackages { pkg = tool "native-first" "2"; };
  initialize = "mkdir -p /srv/target/var/lib/pacman";
  upgrade = install;
  removeFirst = ''
    ${command} -Rns native-first
    orphans=$(${command} -Qdtq || true)
    test -z "$orphans" || ${command} -Rns $orphans
  '';
  removeSecond = "${command} -Rns native-second";
  verify = ''
    ${command} -Qkk > /tmp/native-alpm-verify.log 2>&1
    ! grep -E 'warning:|[1-9][0-9]* altered files' /tmp/native-alpm-verify.log
  '';
}
