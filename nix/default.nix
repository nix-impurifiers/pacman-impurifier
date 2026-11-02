# SPDX-License-Identifier: GPL-3.0-or-later
{ pkgs, coreSrc }:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    namespace = "pacman-impurifier";
  };
  architecture =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64"
    else
      throw "pacman-impurifier: unsupported architecture";
  atom = value: builtins.match "[A-Za-z0-9@:.+_<>=-]+" value != null;
  buildPackage =
    {
      name,
      version,
      release ? "1",
      architecture ? "any",
      payload,
      description ? "Impurified Nix package",
      license ? "LicenseRef-Unknown",
      dependencies ? [ ],
      provides ? [ ],
      conflicts ? [ ],
      replaces ? [ ],
      backupPaths ? [ ],
    }:
    assert lib.assertMsg (builtins.match "[a-z0-9][a-z0-9+.-]+" name != null) "invalid ALPM name";
    assert lib.assertMsg (
      builtins.match "[A-Za-z0-9.+_:]+" version != null
    ) "invalid ALPM pkgver; override native-incompatible upstream versions";
    assert lib.assertMsg (builtins.match "[0-9]+(\\.[0-9]+)*" release != null) "invalid ALPM pkgrel";
    assert lib.assertMsg (lib.all atom (
      dependencies ++ provides ++ conflicts ++ replaces
    )) "invalid ALPM dependency atom";
    pkgs.runCommand "${name}-${version}-${release}-${architecture}.pkg.tar.zst"
      {
        nativeBuildInputs = [
          pkgs.libarchive
          pkgs.zstd
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir root
        cp -r ${payload}/. root/
        chmod -R u+w root
        cat > root/.PKGINFO <<'PKGINFO'
        pkgname = ${name}
        pkgbase = ${name}
        pkgver = ${version}-${release}
        pkgdesc = ${description}
        url = https://github.com/nix-impurifiers/pacman-impurifier
        builddate = 1
        packager = Nix Impurifiers <root@localhost>
        arch = ${architecture}
        license = ${license}
        xdata = pkgtype=pkg
        ${lib.concatMapStringsSep "\n" (value: "depend = ${value}") dependencies}
        ${lib.concatMapStringsSep "\n" (value: "provides = ${value}") provides}
        ${lib.concatMapStringsSep "\n" (value: "conflict = ${value}") conflicts}
        ${lib.concatMapStringsSep "\n" (value: "replaces = ${value}") replaces}
        ${lib.concatMapStringsSep "\n" (path: "backup = ${lib.removePrefix "/" path}") backupPaths}
        PKGINFO
        echo "size = $(du --apparent-size -sb root | cut -f1)" >> root/.PKGINFO
        find root -exec touch -h -d @1 {} +
        bsdtar --format=mtree --options='!all,use-set,type,uid,gid,mode,time,size,sha256,link' \
          -czf "$TMPDIR/mtree.gz" -C root .
        cp "$TMPDIR/mtree.gz" root/.MTREE
        find root -mindepth 1 -printf '%P\0' | sort -z > files
        tar -C root --null --no-recursion --mtime=@1 --owner=0 --group=0 --numeric-owner \
          --zstd -cf "$out" -T "$PWD/files"
      '';
  hasIntegration =
    args:
    (args.configFiles or { }) != { }
    || (args.files or { }) != { }
    || (args.users or { }) != { }
    || (args.directories or { }) != { }
    || (args.systemd or null) != null
    || (args.openrc or null) != null;
  makeIntegrationPackage =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ "systemd" ],
      ...
    }:
    if !(hasIntegration args) then
      null
    else
      let
        payload = core.makePayload (
          (builtins.removeAttrs args [
            "release"
            "hostDependencies"
          ])
          // {
            mode = "integration";
            offline = false;
          }
        );
      in
      buildPackage {
        name = "${payload.name}-integration";
        inherit (payload) version description;
        inherit payload release architecture;
        dependencies = [ "pacman-impurifier>=0.1.0" ] ++ lib.optionals payload.hostEnabled hostDependencies;
        backupPaths = payload.configPaths;
      };
  makePacmanPackage =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ "systemd" ],
      ...
    }:
    let
      payload = core.makePayload (
        (builtins.removeAttrs args [
          "release"
          "hostDependencies"
        ])
        // {
          mode = "application";
        }
      );
    in
    buildPackage {
      name = payload.packageName;
      inherit (payload) version description;
      inherit payload release architecture;
      dependencies = [
        "pacman-impurifier>=0.1.0"
      ]
      ++ lib.optional (hasIntegration args) "${payload.name}-integration=${payload.version}-${release}";
      provides = [ "${payload.name}=${payload.version}" ];
      conflicts = [ "${payload.name}-${if payload.offline then "net" else "offline"}" ];
      replaces = [ "${payload.name}-${if payload.offline then "net" else "offline"}" ];
    };
  makeRuntimePackage =
    {
      nixDependency ? "nix",
      pythonDependency ? "python",
    }:
    let
      tree = core.makeRuntimeTree { binDir = "/usr/bin"; };
    in
    buildPackage {
      name = "pacman-impurifier";
      version = "0.1.0";
      license = "GPL-3.0-or-later";
      description = "Native package intent projected into a Nix profile";
      dependencies = [
        nixDependency
        pythonDependency
      ];
      payload = pkgs.runCommand "pacman-impurifier-runtime-payload" { } ''
        mkdir -p $out/usr/share/libalpm/hooks
        cp -r ${tree}/. $out/
        cat > $out/usr/share/libalpm/hooks/95-pacman-impurifier.hook <<'HOOK'
        [Trigger]
        Operation = Install
        Operation = Upgrade
        Operation = Remove
        Type = Path
        Target = usr/share/nix-profile.d/*.json
        Target = usr/lib/pacman-impurifier/engine.py
        [Action]
        Description = Reconcile Nix application profile
        When = PostTransaction
        Exec = /usr/bin/nix-profile-engine reconcile
        HOOK
      '';
    };
in
{
  inherit (core) engine offlineCache unit;
  inherit
    buildPackage
    makePacmanPackage
    makeIntegrationPackage
    makeRuntimePackage
    ;
  runtimePackage = makeRuntimePackage { };
  makePackage = args: {
    integration = makeIntegrationPackage args;
    net = makePacmanPackage (args // { offline = false; });
    offline = makePacmanPackage (args // { offline = true; });
  };
  makeNetPackage = args: makePacmanPackage (args // { offline = false; });
  makeOfflinePackage = args: makePacmanPackage (args // { offline = true; });
}
