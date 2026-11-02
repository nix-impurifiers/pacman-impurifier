# Testing

`nix flake check -L` runs emitter contracts, the shared engine's unit suite, and real ALPM transactions in QEMU. Offline tests disable networking and assert the application closure is initially absent. Coverage includes failed substitution, recovery, flavor switching, edited configuration, upgrades, accounts/directories, systemd services, lifecycle hooks, administrator intent, removal, GC and native driver-package upgrades that refresh immutable snapshots.

The fixture uses actual pacman and NixOS systemd with mutable native-style unit directories. It is not a complete Arch installation. Host assets use a stable integration package so native configuration backup survives flavor replacement.
