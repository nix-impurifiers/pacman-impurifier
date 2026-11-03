# SPDX-License-Identifier: MIT
"""Emit a native, byte-preserving PKGBUILD from an impurifier ALPM artifact."""
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

artifact, configuration, output = map(Path, sys.argv[1:])
config = json.loads(configuration.read_text())
metadata = {}
for line in subprocess.check_output(["bsdtar", "-xOf", str(artifact), ".PKGINFO"], text=True).splitlines():
    if line.startswith("#") or not line.strip():
        continue
    key, separator, value = line.partition(" = ")
    if not separator:
        raise ValueError("invalid native PKGINFO line")
    metadata.setdefault(key, []).append(value)


def single(key):
    values = metadata.get(key, [])
    if len(values) != 1:
        raise ValueError(f"expected one {key} in PKGINFO")
    return values[0]


name = single("pkgname")
version, release = single("pkgver").rsplit("-", 1)
epoch = None
if ":" in version:
    epoch, version = version.split(":", 1)
    if not epoch.isdecimal():
        raise ValueError("invalid package epoch")
if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", name):
    raise ValueError("invalid package name")
if not re.fullmatch(r"[A-Za-z0-9._+]+", version) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", release):
    raise ValueError("version is incompatible with makepkg")
entries = subprocess.check_output(["bsdtar", "-tf", str(artifact)], text=True).splitlines()
install_entry = next((entry for entry in entries if entry.removeprefix("./") == ".INSTALL"), None)

output.mkdir(parents=True)
filename = "impurifier.pkg.tar.zst"
source = filename
if config["sourceUrl"] is None:
    shutil.copyfile(artifact, output / filename)
else:
    source += "::" + config["sourceUrl"]

lines = ["# SPDX-License-Identifier: MIT", "# Generated from native ALPM metadata; package payload bytes stay unchanged."]
for key, value in [("pkgname", name), ("pkgver", version), ("pkgrel", release), ("pkgdesc", single("pkgdesc"))]:
    lines.append(f"{key}={shlex.quote(value)}")
if epoch is not None:
    lines.append(f"epoch={epoch}")
if "url" in metadata:
    lines.append("url=" + shlex.quote(single("url")))
for key, values in [
    ("arch", [single("arch")]),
    ("license", metadata.get("license", ["LicenseRef-Unknown"])),
    ("depends", metadata.get("depend", [])),
    ("provides", metadata.get("provides", [])),
    ("conflicts", metadata.get("conflict", [])),
    ("replaces", metadata.get("replaces", [])),
    ("backup", metadata.get("backup", [])),
    ("options", ["!strip", "!debug", "!lto", "!purge", "!zipman", "libtool", "staticlibs", "emptydirs", "docs"]),
    ("source", [source]),
    ("noextract", [filename]),
    ("sha256sums", [hashlib.file_digest(artifact.open("rb"), "sha256").hexdigest()]),
]:
    lines.append(key + "=(" + " ".join(map(shlex.quote, values)) + ")")
lines.extend([
    "package() {",
    '  bsdtar --no-same-owner -xf "$srcdir/impurifier.pkg.tar.zst" -C "$pkgdir"',
    '  rm -f "$pkgdir/.PKGINFO" "$pkgdir/.MTREE" "$pkgdir/.BUILDINFO" "$pkgdir/.SIGNATURE" "$pkgdir/.INSTALL"',
    "}",
])
if install_entry is not None:
    (output / "impurifier.install").write_bytes(subprocess.check_output([
        "bsdtar", "-xOf", str(artifact), install_entry,
    ]))
    lines.insert(2, "install=impurifier.install")
(output / "PKGBUILD").write_text("\n".join(lines) + "\n")
