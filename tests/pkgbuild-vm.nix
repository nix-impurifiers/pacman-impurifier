# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  frontend ? "makepkg",
}:
let
  aurSdk = import ./aur-sdk.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "aur-tool-${version}"
      {
        pname = "aur-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/aur-tool
        chmod +x $out/bin/aur-tool
      '';
  recipe =
    version:
    impurifier.makePkgbuild { package = impurifier.makeOfflinePackage { pkg = tool version; }; };
  provider = impurifier.buildPackage {
    name = "native-sdk";
    version = "1";
    provides = [
      "nix"
      "python"
    ];
    payload = pkgs.runCommand "native-sdk-payload" { } ''
      mkdir -p $out/usr/bin
      ln -s ${pkgs.nix}/bin/nix-store $out/usr/bin/nix-store
      ln -s ${pkgs.python3}/bin/python3 $out/usr/bin/python3
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "pacman-impurifier-${frontend}";
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
    users.users.builder = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
    security.sudo.wheelNeedsPassword = false;
    environment.systemPackages =
      pkgs.lib.optional (frontend == "pikaur") aurSdk.pikaur
      ++ pkgs.lib.optional (frontend == "trizen") aurSdk.trizen
      ++ pkgs.lib.optional (frontend == "pacaur") aurSdk.pacaur
      ++ pkgs.lib.optional (frontend == "aura") aurSdk.aura
      ++ pkgs.lib.optional (frontend == "pamac") aurSdk.pamac
      ++ (with pkgs; [
        pacman
        yay
        paru
        nix
        python3
        fakeroot
        libarchive
        zstd
        gzip
        bzip2
        xz
        file
        gawk
        gnused
        gnugrep
        findutils
        diffutils
        coreutils
        binutils
        gcc
        gnumake
        pkg-config
        autoconf
        automake
        libtool
        patch
        which
        git
      ]);
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
    environment.etc."makepkg.conf".source = "${pkgs.pacman}/etc/makepkg.conf";
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /var/lib/pacman/local /var/cache/pacman/pkg /usr/bin /home/builder/v1 /home/builder/v2")
    machine.succeed("cp -r ${recipe "1"}/. /home/builder/v1/; cp -r ${recipe "2"}/. /home/builder/v2/; chown -R builder:users /home/builder; chmod -R u+w /home/builder")
    machine.succeed("pacman --config /etc/pacman.conf -U --noconfirm ${provider}")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    machine.succeed("cp -r /home/builder/v1 /home/builder/damaged; echo damaged >> /home/builder/damaged/impurifier.pkg.tar.zst; chown -R builder:users /home/builder/damaged")
    code, output = machine.execute("su - builder -c 'cd /home/builder/damaged; makepkg --verifysource --noconfirm' 2>&1")
    assert code != 0 and "validity check" in output, output
    code, output = machine.execute("su - builder -c 'cd /home/builder/v1; makepkg --noconfirm' 2>&1")
    assert code != 0 and "pacman-impurifier" in output, output
    machine.succeed("pacman --config /etc/pacman.conf -U --noconfirm ${impurifier.runtimePackage}")
    machine.succeed("su - builder -c 'for dir in /home/builder/v1 /home/builder/v2; do cd $dir; git init -b main; git -c user.name=Fixture -c user.email=fixture@localhost add .; git -c user.name=Fixture -c user.email=fixture@localhost commit -m Recipe; git clone --bare . $dir.git; git remote add origin $dir.git; git fetch origin; git branch --set-upstream-to=origin/main; done'")
    machine.succeed("su - builder -c 'mkdir -p /home/builder/.cache/pacaur'")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    for version in [1, 2]:
        with subtest("native ${frontend} builds and installs version " + str(version)):
            commands = {
                "makepkg": "makepkg --noconfirm -i",
                "yay": "yay -Bi --noconfirm .",
                "paru": "paru -Bi --noconfirm .",
                "pikaur": "pikaur -Pi --noconfirm",
                "trizen": "makepkg --noconfirm && trizen -U --noconfirm ./*.pkg.tar.gz",
                "pacaur": "makepkg --noconfirm && pacaur -U --noconfirm ./*.pkg.tar.gz",
                "aura": "makepkg --noconfirm && aura -U --noconfirm ./*.pkg.tar.gz",
                "pamac": "makepkg --noconfirm && sudo pamac install --no-confirm ./*.pkg.tar.gz",
            }
            command = commands["${frontend}"]
            machine.succeed("setsid --wait timeout --foreground -k 2s 60s su - builder -c 'cd /home/builder/v" + str(version) + "; " + command + "'", timeout=120)
            machine.succeed("test $(/opt/nix/profile/bin/aur-tool) = " + str(version))
            machine.succeed("pacman -Qkk aur-tool-offline")
    machine.succeed("su - builder -c /opt/nix/profile/bin/aur-tool | grep '^2$'")
    machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/aur-tool) = 2")
    remove = "sudo pacman -R --noconfirm aur-tool-offline" if "${frontend}" == "makepkg" else ("sudo pamac remove --no-confirm aur-tool-offline" if "${frontend}" == "pamac" else "${frontend} -R --noconfirm aur-tool-offline")
    machine.succeed("setsid --wait timeout --foreground -k 2s 60s su - builder -c '" + remove + "'")
    machine.succeed("/usr/bin/nix-profile-engine prune --keep 0; nix-store --gc")
    machine.fail("test -e /opt/nix/profile/bin/aur-tool")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
  '';
}
