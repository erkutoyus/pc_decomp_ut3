"""Create a small, unsigned Payload/*.app IPA for SideStore to re-sign."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import zipfile


def clone_app(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if source == destination or source.is_relative_to(destination) or destination.is_relative_to(source):
        raise ValueError('App staging must be separate from the source app')
    if source.suffix != '.app' or destination.suffix != '.app':
        raise ValueError('Expected .app source and destination directories')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        staged = Path(temporary)/source.name
        shutil.copytree(source, staged, symlinks=True)
        if destination.exists():
            shutil.rmtree(destination)
        staged.rename(destination)


def ios_executable(path):
    """Reject accidental macOS/simulator executables before producing an IPA."""
    with path.open('rb') as file:
        header = file.read(32)
        if len(header) != 32:
            return False
        magic, cpu, subtype, kind, commands, size, flags, reserved = struct.unpack('<8I', header)
        if magic != 0xfeedfacf or cpu != 0x0100000c or kind != 2 or size > 16*1024*1024:
            return False
        data = file.read(size)
    at = 0
    for _ in range(commands):
        if at+8 > len(data):
            return False
        command, length = struct.unpack_from('<2I', data, at)
        if length < 8 or at+length > len(data):
            return False
        if command == 0x32 and length >= 24:  # LC_BUILD_VERSION, PLATFORM_IOS
            return struct.unpack_from('<I', data, at+8)[0] == 2
        at += length
    return False


def package(app, output, *, strip_signature=True):
    app, output = Path(app).resolve(), Path(output).resolve()
    if output.suffix != '.ipa' or output.is_relative_to(app):
        raise ValueError('Choose an .ipa output outside the source app')
    info = plistlib.loads((app/'Info.plist').read_bytes())
    executable = info.get('CFBundleExecutable', '')
    if not executable or '/' in executable or not ios_executable(app/executable):
        raise ValueError('Expected a physical-device iOS ARM64 executable, not a macOS/simulator build')
    if info.get('CFBundlePackageType') != 'APPL' or not info.get('CFBundleIdentifier'):
        raise ValueError('Incomplete iOS bundle metadata')
    for path in app.rglob('*'):
        if path.is_symlink():
            if not path.resolve().is_relative_to(app) or not path.resolve().exists():
                raise ValueError('App contains a dangling or external symbolic link')
        if path.name.lower() in ['cdkey.txt', 'game', 'userdata'] or path.suffix.lower() in ['.exe', '.dll', '.ue3profile']:
            raise ValueError('Small IPA must not contain original game assets, keys or saves')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent, prefix='.ut3-ipa-') as temp:
        root = Path(temp)
        staged = root/'Payload'/app.name
        staged.parent.mkdir()
        shutil.copytree(app, staged, symlinks=True)
        for path in sorted(staged.rglob('*'), reverse=True):
            if path.name == '_CodeSignature' and path.is_dir():
                shutil.rmtree(path)
            elif path.is_file() and path.name in ['embedded.mobileprovision', 'archived-expanded-entitlements.xcent']:
                path.unlink()
        if strip_signature:
            for path in [*sorted((staged/'Frameworks').glob('*.dylib')), staged/executable]:
                subprocess.run(['codesign', '--remove-signature', str(path)], check=True)
        archive = root/'result.ipa'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as file:
            for path in sorted((root/'Payload').rglob('*')):
                name = path.relative_to(root).as_posix()
                if path.is_symlink():
                    item = zipfile.ZipInfo(name)
                    item.create_system = 3
                    item.external_attr = (stat.S_IFLNK | 0o777) << 16
                    file.writestr(item, os.readlink(path))
                elif path.is_file():
                    file.write(path, name)
        with zipfile.ZipFile(archive) as file:
            if file.testzip() is not None:
                raise ValueError('IPA CRC verification failed')
            archived = plistlib.loads(file.read('Payload/'+app.name+'/Info.plist'))
            if archived != info or 'Payload/'+app.name+'/'+executable not in file.namelist():
                raise ValueError('IPA Payload verification failed')
        archive.replace(output)
    receipt = {'format':'Payload/*.app','platform':'ios-arm64-device','signing':'unsigned; SideStore must re-sign before installation',
               'bundle_identifier':info['CFBundleIdentifier'],'display_name':info.get('CFBundleDisplayName'),
               'game_assets_bundled':False,'bytes':output.stat().st_size,
               'sha256':None}
    with output.open('rb') as file:
        receipt['sha256'] = hashlib.file_digest(file, 'sha256').hexdigest()
    output.with_suffix('.ipa.json').write_text(json.dumps(receipt, indent=2)+'\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    receipt = package(args.app, args.output)
    print(f'Ready: {args.output} ({receipt["bytes"]/1024/1024:.1f} MiB). Sign/install with SideStore; copy game data separately.')


if __name__ == '__main__':
    main()
