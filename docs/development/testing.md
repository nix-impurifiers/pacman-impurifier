# Testing

`nix flake check -L` runs emitter contracts, the shared engine's unit suite, and real ALPM transactions in QEMU. Offline tests disable networking and assert the application closure is initially absent. Coverage includes failed substitution, recovery, flavor switching, edited configuration, upgrades, accounts/directories, systemd services, lifecycle hooks, administrator intent, removal, GC and native driver-package upgrades that refresh immutable snapshots.

The fixture uses actual pacman and NixOS systemd with mutable native-style unit directories. It is not a complete Arch installation. Host assets use a stable integration package so native configuration backup survives flavor replacement.

The PKGBUILD matrix uses actual makepkg, Yay, Paru, Pikaur, Aura, Pacaur,
Trizen and Pamac CLI with an ordinary builder
account and real sudo in isolated VMs. It checks source corruption, missing
runtime dependencies, two native builds/installations, native ownership checks,
unprivileged launch, and Nix GC retention/release. Helpers receive real local Git
repositories. Yay/Paru/Pikaur run native recipe builds; Aura/Pacaur/Trizen/Pamac
install the real makepkg output through their own native client operation.
Removal also runs through each client. All tests disable external networking. This tests their local build integration, not remote AUR discovery or
publication. The fixture's native provider owns links to the preinstalled Nix
and Python programs; it does not install Nix.

The signed-repository VM generates an ephemeral GPG key, initializes pacman's
actual keyring, signs packages and repository databases with upstream tools,
and requires both signatures. It checks unsigned package and tampered database
rejection, solver-selected runtime dependencies, `pacman -Qkk` integrity,
repository upgrades, recursive removal and GC. Archive headers and `.MTREE`
both record root ownership. Runtime removal reconciles and prunes while its
engine and dependencies are still installed.

Helpers use pinned upstream SDK builds with their original licenses and notices. pyalpm links the same native libalpm as pacman; no package manager
logic is replaced. Trizen's SDK relocates FHS tool paths and provides its real
Perl dependencies; Pacaur receives the native makepkg library path. Pamac uses
the native library and CLI with AppStream disabled. Remote AUR submission,
discovery and dependency fetching, Pamac GTK/polkit GUI interactions, and a full
Arch/Manjaro installation remain additional coverage.
