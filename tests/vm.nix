# SPDX-License-Identifier: GPL-3.0-or-later
{ pkgs, impurifier }:
let
  tool =
    version:
    pkgs.runCommand "alpm-tool-${version}"
      {
        pname = "alpm-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/alpm-tool
        chmod +x $out/bin/alpm-tool
      '';
  app =
    offline: version:
    impurifier.makePacmanPackage {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/alpm-tool.conf" = pkgs.writeText "alpm-tool.conf" "version=${version}\n";
    };
  integration =
    version:
    impurifier.makeIntegrationPackage {
      pkg = tool version;
      configFiles."/etc/alpm-tool.conf" = pkgs.writeText "alpm-tool.conf" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "alpm-service-${version}"
      {
        pname = "alpm-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/alpm-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/alpm-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/alpm-service
      '';
  service =
    version:
    impurifier.makePackage {
      pkg = daemon version;
      users.alpm-service = { };
      directories."/var/lib/alpm-service" = {
        owner = "alpm-service:alpm-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('alpm-service')"
          test -x /opt/nix/profile/bin/alpm-service
          echo initialized > /var/lib/alpm-service/initialized
        '';
        onUpgrade = ''
          echo ${version} > /var/lib/alpm-service/migrated
        '';
      };
      systemd.unit = pkgs.writeText "alpm-service.service" ''
        [Service]
        Type=exec
        User=alpm-service
        ExecStart=/opt/nix/profile/bin/alpm-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  provider = impurifier.buildPackage {
    name = "vm-runtime";
    version = "1";
    provides = [
      "nix"
      "python"
      "systemd"
    ];
    payload = pkgs.runCommand "alpm-runtime-payload" { } ''
      mkdir -p $out/usr/share/impurifier-vm
      echo preinstalled > $out/usr/share/impurifier-vm/runtime
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "pacman-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgs.pacman
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
      "L+ /usr/bin/nix-store - - - - ${pkgs.nix}/bin/nix-store"
    ];
    environment.etc."pacman.conf".text = ''
      [options]
      Architecture = auto
      SigLevel = Never
      LocalFileSigLevel = Never
      HookDir = /usr/share/libalpm/hooks/
      DBPath = /var/lib/pacman/
      CacheDir = /var/cache/pacman/pkg/
      LogFile = /var/log/pacman.log
    '';
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /var/lib/pacman/local /var/cache/pacman/pkg /tmp/packages")
    machine.succeed("cp ${app false "1"} /tmp/packages/net1.pkg.tar.zst; cp ${app true "1"} /tmp/packages/offline1.pkg.tar.zst; cp ${app true "2"} /tmp/packages/offline2.pkg.tar.zst; cp ${integration "1"} /tmp/packages/integration1.pkg.tar.zst; cp ${integration "2"} /tmp/packages/integration2.pkg.tar.zst")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("cp ${(service "1").offline} /tmp/packages/service1.pkg.tar.zst; cp ${(service "1").integration} /tmp/packages/service-integration1.pkg.tar.zst; cp ${(service "2").offline} /tmp/packages/service2.pkg.tar.zst; cp ${(service "2").integration} /tmp/packages/service-integration2.pkg.tar.zst")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    pacman = "pacman --config /etc/pacman.conf "
    machine.succeed(pacman + "-U --noconfirm ${provider} ${impurifier.runtimePackage}")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("failed post-transaction substitution preserves the old profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        output = machine.execute(pacman + "-U --noconfirm /tmp/packages/net1.pkg.tar.zst /tmp/packages/integration1.pkg.tar.zst 2>&1")[1]
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline provider switch recovers without a network"):
        machine.succeed("printf 'y\\ny\\n' | " + pacman + "-U /tmp/packages/offline1.pkg.tar.zst")
        machine.succeed("test $(/opt/nix/profile/bin/alpm-tool) = 1")
        machine.fail(pacman + "-Q alpm-tool-net")
    with subtest("native backup configuration survives switches and upgrades"):
        machine.succeed("echo local > /etc/alpm-tool.conf")
        machine.succeed("printf 'y\\ny\\n' | " + pacman + "-U /tmp/packages/net1.pkg.tar.zst")
        machine.succeed("grep local /etc/alpm-tool.conf")
        machine.succeed("printf 'y\\ny\\n' | " + pacman + "-U /tmp/packages/offline2.pkg.tar.zst /tmp/packages/integration2.pkg.tar.zst")
        machine.succeed("grep local /etc/alpm-tool.conf; test $(/opt/nix/profile/bin/alpm-tool) = 2")
    with subtest("post-transaction hook batches descriptor changes"):
        output = machine.succeed(pacman + "-U --noconfirm ${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-a";
            version = "1";
          }
        } ${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-b";
            version = "1";
          }
        }")
        assert output.count("activated ") == 1, output
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed(pacman + "-R --noconfirm batch-a-offline batch-b-offline")
    with subtest("native service integration provisions accounts and preserves administrator intent"):
        machine.succeed(pacman + "-U --noconfirm /tmp/packages/service1.pkg.tar.zst /tmp/packages/service-integration1.pkg.tar.zst")
        machine.wait_for_unit("alpm-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/alpm-service/version")
        machine.succeed("id alpm-service; test $(stat -c %U /var/lib/alpm-service) = alpm-service")
        machine.succeed(pacman + "-U --noconfirm /tmp/packages/service2.pkg.tar.zst /tmp/packages/service-integration2.pkg.tar.zst")
        machine.wait_until_succeeds("grep '^2$' /var/lib/alpm-service/version")
        machine.succeed("grep initialized /var/lib/alpm-service/initialized; grep '^2$' /var/lib/alpm-service/migrated")
        machine.succeed("systemctl disable --now alpm-service.service")
        machine.succeed(pacman + "-U --noconfirm /tmp/packages/service1.pkg.tar.zst /tmp/packages/service-integration1.pkg.tar.zst")
        machine.fail("systemctl is-active --quiet alpm-service.service")
        machine.fail("systemctl is-enabled --quiet alpm-service.service")
        machine.succeed("systemctl enable --now alpm-service.service")
        machine.succeed(pacman + "-R --noconfirm alpm-service-offline alpm-service-integration")
        machine.fail("systemctl is-active --quiet alpm-service.service")
    with subtest("GC roots, native removal and generation pruning"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/alpm-tool) = 2")
        machine.succeed(pacman + "-R --noconfirm alpm-tool-offline alpm-tool-integration")
        machine.fail("test -e /opt/nix/profile/bin/alpm-tool")
        machine.succeed("grep local /etc/alpm-tool.conf.pacsave")
        machine.succeed("/usr/bin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
