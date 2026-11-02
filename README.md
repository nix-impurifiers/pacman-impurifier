# pacman-impurifier

Emit native ALPM packages backed by the shared [impurifier engine](https://github.com/nix-impurifiers/impurifier) and an atomic, GC-rooted `/opt/nix/profile`.

```nix
let impurifier = inputs.pacman-impurifier.lib.pacman-impurifier { inherit pkgs; };
in impurifier.makePackage { pkg = pkgs.hello; }
```

The result contains `net`, `offline`, and `integration` (null for applications without host assets). Net artifacts substitute through the host's configured Nix caches. Offline artifacts carry a complete local closure cache and disable network substitution and remote builders during import.

Install the runtime package and a working Nix and Python runtime first. `makeRuntimePackage { nixDependency = "nix"; }` accepts a consumer-selected native Nix dependency. Providing Nix through an impure native package is deferred installer work, not excluded from the project.

For applications with configuration, files, accounts, directories or services, install the stable integration package alongside the selected flavor. Upgrade both in one pacman transaction. Keeping host assets in a stable package lets native `backup` handling preserve edited configuration across flavor switches; removal follows native `.pacsave` behavior. No integration artifact is needed for a pure command-line application.

```sh
sudo pacman -U app-integration.pkg.tar.zst app-offline.pkg.tar.zst
```

`configFiles`, `files`, `users`, `directories`, and `systemd` use the common payload DSL. Service commands should use `/opt/nix/profile/bin/<tool>`. Service policy fields `enable`, `startOnInstall`, `restartOnUpgrade`, and `stopOnRemove` default to true. Accounts and persistent directories survive removal. Administrator stops and disables survive upgrades.

An ALPM post-transaction hook batches descriptor changes. A hook failure can leave the native transaction committed; failed fetching or composition preserves the previous profile. Inspect transaction diagnostics and retry `/usr/bin/nix-profile-engine reconcile` after fixing the cause. Service activation failures can occur after publication and retain recovery state. `status` describes the published profile; `prune --keep 2` removes unused generations while retaining active and pending activation roots.

```sh
nix flake check -L
```

Checks cover native archive metadata and reference-free artifact closures, engine contracts, and a QEMU VM using actual pacman, Nix and systemd. The VM disables networking and exercises failed substitution, offline recovery, flavor switching, edited configuration, upgrades, transaction batching, service accounts/directories, administrator intent, removal and GC. It runs NixOS with native-style mutable service directories; a complete Arch installation remains additional compatibility coverage.

GPL-3.0-or-later.

Lifecycle hooks `lifecycle.onInstall` and `lifecycle.onUpgrade` accept shell bodies. They run as root after accounts/directories exist and the new profile is published, before service activation. Use `/opt/nix/profile/bin/<tool>` for projected commands and declare native dependencies for other commands. Install hooks run until the application's first successful activation; upgrade hooks run when its output, version or hook revision changes, including native downgrades. A failed hook leaves activation pending and may be retried, so hooks must be idempotent. They do not provide database rollback or exactly-once execution. Flavor-only changes to the same application do not rerun completed hooks.
