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

MIT.

Lifecycle hooks `lifecycle.onInstall` and `lifecycle.onUpgrade` accept shell bodies. They run as root after accounts/directories exist and the new profile is published, before service activation. Use `/opt/nix/profile/bin/<tool>` for projected commands and declare native dependencies for other commands. Install hooks run until the application's first successful activation; upgrade hooks run when its output, version or hook revision changes, including native downgrades. A failed hook leaves activation pending and may be retried, so hooks must be idempotent. They do not provide database rollback or exactly-once execution. Flavor-only changes to the same application do not rerun completed hooks.

Host-library bridging is opt-in:

```nix
hardware = {
  libraries."libdriver.so.1" = "/usr/lib/libdriver.so.1";
  programs = [ "my-tool" ];
  preload = []; # Optional subset of declared library names.
};
```

The engine captures explicitly selected ELF files into an immutable Nix-store directory, roots it with the generation, and wraps the selected application's `bin` commands with `LD_LIBRARY_PATH` and optional `LD_PRELOAD`. Native library-directory transaction hooks reconcile driver upgrades. Changed snapshots create a new generation and restart previously running managed services according to their upgrade policy. Older generations retain their original user-space snapshot. Missing or unreadable libraries abort before profile publication; the existing snapshot remains usable.

Consumers select compatible libraries, their non-Nix dependencies, paths and native package dependencies. This does not discover a GPU stack, validate its ABI, rebind already-running processes, or roll back kernel modules. GPU user/kernel compatibility and real-device behavior need hardware tests. Sources outside `/usr/lib`, `/usr/lib64`, `/lib` and `/lib64` need explicit reconciliation after updates. This is a bounded runtime bridge, not automatic GPU compatibility.

The exported `runtimeVersion` follows the pinned core source timestamp. Application dependencies require that runtime version or newer, rather than accepting every engine as `0.1.0`. This supports ordinary native engine upgrades without project release tags. Consumer-provided Nix dependency expressions remain independent of the engine's own native version.

`makePkgbuild { package = impurifier.makeOfflinePackage { pkg = pkgs.hello; }; }`
emits a native `PKGBUILD` and its source artifact. Build it as an ordinary user
with `makepkg -i`, or commit the directory to a local Git repository and use
Yay/Paru's `-Bi` operation or Pikaur's `-Pi` operation. The recipe preserves native dependencies, conflicts,
backup paths and licenses, verifies the artifact SHA256, and disables makepkg's
payload rewriting. A `sourceUrl` HTTP(S) override emits a recipe referencing a
published artifact instead of including a local copy. Publishing that artifact
and submitting a package to the AUR remain publisher actions; this factory does
not submit anything. Native `.INSTALL` scriptlets are preserved as makepkg install scripts.

A signed-repository VM and native helper VMs cover makepkg, Yay, Paru, Pikaur,
Aura, Pacaur, Trizen and Pamac CLI. See [testing](docs/development/testing.md)
for tested paths and remaining compatibility coverage.


## Native-owned closures and optional bundled Nix

`makeNativePackages { pkg = myApplication; programs = [ "my-command" ]; }` returns
a directory of native packages: one application package exporting commands, and
one package per immutable runtime store object. Exact native dependencies retain
shared objects. Native tools own the files and package database. The target needs
no Nix executable, daemon, SQLite database, realization hooks or shared profile.
Files remain at their original absolute paths; no relocation is performed.
Inputs may come from any compatible Nix producer. This API currently covers
payload files and command exports rather than the profile-mode host lifecycle DSL.

Install the collection with ordinary native tools, or publish its artifacts in
a native repository. Local-file installation may mark supplied dependency
packages explicit; native dependency marks and cleanup policy remain the caller's
choice. Upgrades can leave old immutable objects orphaned, so include native
orphan cleanup when desired. Do not register these same paths into a Nix-managed
store: Nix GC and native ownership must not overlap.

`makeRuntimePackage` additionally accepts `bundledNixStore` (a supplied static ELF
`nix-store` executable) and nonempty `bundledNixNotices`. A bundle makes the
external native Nix dependency optional and marks the runtime package with its
actual target architecture. A compatible external client is preferred; otherwise
the private bundled client is used. Explicit `nixDependency` still requests a
native provider. Client selection never changes store ownership or trust, and a
failed mutation is not retried with another client. This is not daemon setup.

`native-vm` tests isolated target-root installation, execution, upgrades, shared
references, checksum verification and final cleanup without target-side Nix.
`bundled-vm` reruns native lifecycle and recovery tests without an external client
on the engine's discovery paths, using the actual static client. Those lifecycle
fixtures still supply an existing Nix store; database-free operation is established
by the separate native-owned test, not by the bundled client.

For local ALPM archives, mark store-object packages as dependencies if desired.
Use native recursive removal and orphan queries to clean objects left by upgrades.
