# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  tool =
    version:
    pkgs.runCommand "repository-tool-${version}"
      {
        pname = "repository-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/repository-tool
        chmod +x $out/bin/repository-tool
      '';
  app = version: impurifier.makeOfflinePackage { pkg = tool version; };
  provider = impurifier.buildPackage {
    name = "native-runtime";
    version = "1";
    provides = [
      "nix"
      "python"
    ];
    payload = pkgs.runCommand "native-runtime-links" { } ''
      mkdir -p $out/usr/bin
      ln -s ${pkgs.nix}/bin/nix-store $out/usr/bin/nix-store
      ln -s ${pkgs.python3}/bin/python3 $out/usr/bin/python3
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "pacman-impurifier-signed-repository";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 1024;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgs.pacman
      pkgs.gnupg
      pkgs.nix
      pkgs.python3
    ];
    environment.etc."pacman.conf".text = ''
      [options]
      Architecture = auto
      SigLevel = Required DatabaseRequired
      LocalFileSigLevel = Required
      GPGDir = /etc/pacman.d/gnupg/
      HookDir = /usr/share/libalpm/hooks/
      DBPath = /var/lib/pacman/
      CacheDir = /var/cache/pacman/pkg/
      LogFile = /var/log/pacman.log
      [fixture]
      Server = file:///packages/repo
    '';
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /packages/repo /packages/next /etc/pacman.d/gnupg /usr/bin /var/lib/pacman/local /var/cache/pacman/pkg /root/.gnupg; chmod 700 /root/.gnupg")
    machine.succeed("cp ${provider} /packages/repo/native-runtime-1-1-any.pkg.tar.zst; cp ${impurifier.runtimePackage} /packages/repo/runtime.pkg.tar.zst; cp ${app "1"} /packages/repo/app-1.pkg.tar.zst; cp ${app "2"} /packages/next/app-2.pkg.tar.zst")
    machine.succeed("gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key 'VM Fixture <fixture@localhost>' ed25519 sign 0 </dev/null; gpg --export > /packages/key.gpg; pacman-key --init; pacman-key --add /packages/key.gpg; pacman-key --lsign-key fixture@localhost")
    machine.succeed("for pkg in /packages/repo/*.zst /packages/next/*.zst; do gpg --batch --detach-sign $pkg; done; cd /packages/repo; repo-add --sign fixture.db.tar.gz *.zst")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    machine.succeed("pacman -Sy --noconfirm")
    with subtest("native package signature policy rejects unsigned artifacts"):
        machine.succeed("cp /packages/repo/app-1.pkg.tar.zst /packages/unsigned.pkg.tar.zst")
        machine.fail("pacman -U --noconfirm /packages/unsigned.pkg.tar.zst")
        machine.fail("pacman -Q repository-tool-offline")
    with subtest("native signed repository resolves runtime dependencies"):
        machine.succeed("pacman -S --noconfirm repository-tool-offline")
        machine.succeed("test $(/opt/nix/profile/bin/repository-tool) = 1; pacman -Qkk repository-tool-offline")
    with subtest("tampered signed database is rejected"):
        machine.succeed("cp /packages/repo/fixture.db.tar.gz /packages/database.good; printf tamper >> /packages/repo/fixture.db.tar.gz")
        code, output = machine.execute("pacman -Syy --noconfirm 2>&1")
        assert code != 0 and "signature" in output, output
        machine.succeed("cp /packages/database.good /packages/repo/fixture.db.tar.gz; pacman -Syy --noconfirm")
    with subtest("signed repository upgrade and rooted garbage collection"):
        machine.succeed("cp /packages/next/* /packages/repo/; cd /packages/repo; repo-add --sign fixture.db.tar.gz app-2.pkg.tar.zst; pacman -Syyu --noconfirm")
        machine.succeed("test $(/opt/nix/profile/bin/repository-tool) = 2; nix-store --gc; test $(/opt/nix/profile/bin/repository-tool) = 2")
    machine.succeed("pacman -Rs --noconfirm repository-tool-offline; nix-store --gc")
    machine.fail("pacman -Q pacman-impurifier")
    machine.fail("test -e /opt/nix/profile/bin/repository-tool")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
  '';
}
