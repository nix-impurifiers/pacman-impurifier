# SPDX-License-Identifier: MIT
"""Compile immutable object trees into native ALPM packages."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

collection, destination = map(Path, sys.argv[1:3])
architecture = sys.argv[3]
destination.mkdir()
for package in json.loads((collection / 'packages.json').read_text()):
    record = json.loads((collection / package / 'metadata.json').read_text())
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary) / 'root'
        shutil.copytree(collection / package / 'tree', root, symlinks=True)
        subprocess.run(['chmod', '-R', 'u+w', str(root)], check=True)
        metadata = (f'pkgname = {record["name"]}\npkgbase = {record["name"]}\n'
                    f'pkgver = {record["version"]}-1\narch = {architecture}\n'
                    'pkgdesc = Native-owned Nix-built payload\nlicense = LicenseRef-Unknown\n'
                    'builddate = 1\npackager = Nix Impurifiers\nxdata = pkgtype=pkg\n')
        metadata += ''.join(f'depend = {name}=1-1\n' for name in record['dependencies'])
        metadata += 'size = ' + subprocess.check_output(['du', '--apparent-size', '-sb', str(root)], text=True).split()[0] + '\n'
        (root / '.PKGINFO').write_text(metadata)
        subprocess.run(['find', str(root), '-exec', 'touch', '-h', '-d', '@1', '{}', '+'], check=True)
        mtree = Path(temporary) / 'mtree.gz'
        subprocess.run(['bsdtar', '--uid', '0', '--gid', '0', '--format=mtree',
                        '--options=!all,use-set,type,uid,gid,mode,time,size,sha256,link',
                        '-czf', str(mtree), '-C', str(root), '.'], check=True)
        shutil.copy2(mtree, root / '.MTREE')
        subprocess.run(['touch', '-d', '@1', str(root / '.MTREE')], check=True)
        files = subprocess.check_output(['find', '.', '-mindepth', '1', '-printf', r'%P\0'], cwd=root)
        artifact = destination / f'{record["name"]}-{record["version"]}-1-{architecture}.pkg.tar.zst'
        subprocess.run(['tar', '--null', '--no-recursion', '--mtime=@1', '--owner=0', '--group=0',
                        '--numeric-owner', '--zstd', '-cf', str(artifact), '-T', '-'],
                       input=b'\0'.join(sorted(files.rstrip(b'\0').split(b'\0'))) + b'\0', cwd=root, check=True)
