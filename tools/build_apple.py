"""One-command Apple builds. Shell entry points select a suitable Python interpreter."""
import argparse
import contextlib
import fcntl
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import platform
import plistlib
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'build/apple'
PINS = json.loads((ROOT / 'config/apple-dependencies.json').read_text())
PYTHON_PACKAGES = {'capstone': '5.0.7', 'pefile': '2024.8.26', 'unicorn': '2.1.4',
                   'meson': '1.9.1', 'pycdlib': '1.14.0'}


def run(*args, **kwargs):
    print('+ ' + shlex.join(str(x) for x in args), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True, **kwargs)


def digest(path):
    with Path(path).open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def bootstrap(offline=False):
    """Never install Python packages into the user's system environment."""
    venv = CACHE / 'venv'
    python = venv / 'bin/python'
    if not python.exists():
        run(sys.executable, '-m', 'venv', venv)
    if Path(sys.prefix).resolve() != venv.resolve():
        os.execv(str(python), [str(python), '-B', str(Path(__file__).resolve()), *sys.argv[1:]])
    missing = []
    for name, version in PYTHON_PACKAGES.items():
        try:
            installed = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            installed = None
        if installed != version:
            missing.append(f'{name}=={version}')
    if missing:
        if offline:
            raise ValueError("Missing pinned Python packages: "+", ".join(missing)+". Rerun without --offline once.")
        run(python, '-m', 'pip', 'install', '--disable-pip-version-check', *missing)
    return python


def download(spec, path, *, existing=(), offline=False):
    """Publish a downloaded dependency only after its exact SHA-256 matches."""
    path = Path(path)
    for candidate in [path, *existing]:
        candidate = Path(candidate)
        if candidate.is_file() and digest(candidate) == spec['sha256']:
            return candidate.resolve()
    if offline:
        raise ValueError(f'Missing pinned dependency: {path.name}. Rerun without --offline to download it.')
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + '.download')
    run('curl', '--fail', '--location', '--retry', '3', '--proto', '=https', '--proto-redir', '=https',
        '--connect-timeout', '30', '--output', partial, spec['url'])
    if digest(partial) != spec['sha256']:
        partial.unlink()
        raise ValueError(f'{path.name}: download hash mismatch; refusing a different dependency version')
    partial.replace(path)
    return path.resolve()


def extract_tree(archive, directory, member_root):
    directory = Path(directory)
    if directory.exists():
        return
    directory.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=directory.parent) as temp:
        with tarfile.open(archive) as source:
            source.extractall(temp, filter='data')
        extracted = Path(temp) / member_root
        if not extracted.is_dir():
            raise ValueError(f'Unexpected archive layout: {archive}')
        extracted.rename(directory)


def sdk(args):
    if args.sdk:
        result = args.sdk.expanduser().resolve()
    else:
        candidates = [CACHE / 'phase3-inputs/VulkanSDK/macOS', CACHE / 'deps/VulkanSDK/macOS',
                      Path.home() / 'VulkanSDK' / PINS['sdk']['version'] / 'macOS']
        result = next((p for p in candidates if (p/'include/vulkan/vulkan.h').exists()), None)
        if result is None:
            archive = download(PINS['sdk'], CACHE/'downloads/vulkan-sdk.zip', offline=args.offline)
            unpacked = CACHE/'deps/sdk-installer'
            unpacked.mkdir(parents=True, exist_ok=True)
            run('ditto', '-x', '-k', archive, unpacked)
            installers = list(unpacked.glob('*.app/Contents/MacOS/vulkansdk-*'))
            if len(installers) != 1:
                raise ValueError('Cannot locate pinned Vulkan SDK installer')
            destination = CACHE/'deps/VulkanSDK'
            run(installers[0], '--root', destination, '--accept-licenses', '--default-answer',
                '--confirm-command', 'install', 'com.lunarg.vulkan.core')
            result = destination/'macOS'
    for name in ['include/vulkan/vulkan.h', 'bin/glslangValidator', 'lib/libvulkan.1.dylib',
                 'lib/MoltenVK.xcframework/ios-arm64/libMoltenVK.a']:
        if not (result/name).is_file():
            raise ValueError(f'The pinned Vulkan SDK is incomplete: {result/name}')
    for name, expected in PINS["sdk"]["files"].items():
        if digest(result/name) != expected:
            raise ValueError(f"Vulkan SDK differs from the pinned release: {name}")
    return result.resolve()


def dxvk_source(args):
    # Existing fully pinned checkouts are validated again by the original builder.
    candidate = CACHE/'phase3-inputs/dxvk-upstream'
    if (candidate/'src/d3d9/d3d9_device.cpp').exists():
        return candidate
    destination = CACHE/'deps/dxvk-upstream'
    for spec in PINS['dxvk_archives']:
        archive = download(spec, CACHE/'downloads'/spec['file'], offline=args.offline)
        target = destination if spec['destination'] == '.' else destination/spec['destination']
        # Git archives contain empty submodule directories, not their sources.
        if target.is_dir() and not any(target.iterdir()):
            target.rmdir()
        extract_tree(archive, target, spec['directory'])
    return destination


def vc80(args, game):
    specs = [x for x in json.loads((ROOT/'config/modules.json').read_text())['modules']
             if x['name'] in ['msvcr80', 'msvcp80']]
    choices = [args.vc80_root] if args.vc80_root else [CACHE/'vc80', game/'Binaries', game]
    for directory in choices:
        if directory and all((directory/x['file']).is_file() and digest(directory/x['file']) == x['sha256'] for x in specs):
            return directory.resolve()
    if args.vc80_root:
        raise ValueError('--vc80-root does not contain both exact pinned VC80 8.0.50727.9680 x86 DLLs')
    if not shutil.which('wimlib-imagex'):
        raise ValueError('The exact VC80 inputs are missing. Run: brew install wimlib, then repeat this command. '
                         'Alternatively use --vc80-root /folder/with/the/two/pinned/DLLs.')
    print('Preparing two pinned CRT files as data from the official Microsoft evaluation ISO (5.1 GB download). '
          'No Windows installation or emulation is used.', flush=True)
    iso = args.windows_iso
    if iso:
        if digest(iso) != PINS['windows_iso']['sha256']:
            raise ValueError('Windows ISO differs from the pinned evaluation image')
    else:
        iso = download(PINS['windows_iso'], CACHE/'downloads/windows-ltsc.iso',
                       existing=[CACHE/'crt-metadata/windows-ltsc.iso'], offline=args.offline)
    import pycdlib
    wim = CACHE/'downloads/install.wim'
    wim.parent.mkdir(parents=True, exist_ok=True)
    # Re-extract from the authenticated ISO; do not trust a stale partial WIM.
    reader = pycdlib.PyCdlib()
    try:
        reader.open(str(iso))
        reader.get_file_from_iso(local_path=str(wim), udf_path='/sources/install.wim')
    finally:
        reader.close()
    target = CACHE/'vc80'
    target.mkdir(parents=True, exist_ok=True)
    run('wimlib-imagex', 'extract', wim, '1', *[x['path'].replace('/', '\\') for x in specs],
        '--dest-dir='+str(target), '--no-acls', '--no-attributes')
    if not all((target/x['file']).is_file() and digest(target/x['file']) == x['sha256'] for x in specs):
        raise ValueError('Extracted CRT files do not match the required hashes')
    wim.unlink()  # Generated extraction scratch; keep the authenticated ISO and verified DLLs.
    return target


def verify_game(game):
    for directory in ['Binaries', 'Engine', 'UTGame']:
        if not (game/directory).is_dir():
            raise ValueError(f'Choose the complete Steam UT3 folder containing Binaries, Engine and UTGame: missing {directory}')
    for row in json.loads((ROOT/'config/inputs.json').read_text())['modules']:
        path = game/row['path']
        if not path.is_file() or path.stat().st_size != row['size'] or digest(path) != row['sha256']:
            raise ValueError(f'Original game input differs from the supported Steam version: {row["path"]}. '
                             'Verify the game in Steam; do not use a modified EXE.')
    print('PASS: all 41 pinned original game inputs verified (read-only).', flush=True)


def ensure_lift(python, game, crt):
    from lift_build import generated_sources
    generated = ROOT/'generated'
    try:
        generated_sources(generated)
        expected = {x['file'] for x in json.loads((ROOT/'config/modules.json').read_text())['modules']}
        import re
        actual = set(re.findall(r'^\s*\{\s*"([^"]+)"', (generated/'modules.inc').read_text(), re.M))
        if actual != expected:
            raise ValueError('incomplete lift')
        print('Reusing complete, verified original lift; original generated sources remain unchanged.', flush=True)
    except (OSError, ValueError, KeyError):
        print('Generating all 20 pinned modules. First build takes substantially longer.', flush=True)
        run(python, '-B', ROOT/'tools/lift_ut3.py', '--game-root', game, '--vc80-root', crt)
        generated_sources(generated)


def renderer_and_audio(args, python, vulkan):
    renderer = CACHE/('ios-dxvk' if args.target == 'ios' else 'macos-dxvk')
    audio = CACHE/('ios-openal' if args.target == 'ios' else 'macos-openal')
    run(python, '-B', ROOT/('tools/build_dxvk_ios.py' if args.target == 'ios' else 'tools/build_dxvk_macos.py'),
        '--source', dxvk_source(args), '--sdk', vulkan, '--meson', python.parent/'meson', '--build', renderer)
    archive = download(PINS['openal'], CACHE/'downloads/openal-soft.tar.gz',
                       existing=[CACHE/'phase4-inputs/openal-soft.tar.gz'], offline=args.offline)
    extra = ['--ios'] if args.target == 'ios' else []
    run(python, '-B', ROOT/'tools/build_openal_macos.py', '--archive', archive, '--build', audio, *extra)
    return renderer/'src/d3d9/libdxvk_d3d9.dylib', audio/'libopenal.1.25.2.dylib', audio.with_name(audio.name+'-source-'+PINS['openal']['revision'][:12])/'include'


def stage_notices(app, target, vulkan):
    directory = app/('Contents/Resources/Licenses' if target=='macos' else 'Licenses')
    directory.mkdir(parents=True,exist_ok=True)
    for source,name in [(ROOT/'LICENSE','Port-GPL-3.0.txt'),(ROOT/'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'),
                        (ROOT/'reference/dxvk/LICENSE','DXVK-LICENSE.txt'),
                        (ROOT/'reference/dxvk/include/native/directx/COPYING.MinGW-w64.txt','DirectX-Headers-COPYING.txt')]:
        shutil.copy2(source,directory/name)
    for source in (ROOT/'reference/audio-runtime/licenses').glob('*.txt'):
        shutil.copy2(source,directory/source.name)
    sdk_notice=vulkan.parent/'Licenses/LICENSE.txt'
    if sdk_notice.is_file():shutil.copy2(sdk_notice,directory/'Vulkan-SDK-NOTICE.txt')
    (directory/'BUILD-SOURCES.txt').write_text('Apple dependencies and exact source revisions: config/apple-dependencies.json in the source checkout.\n'
        'OpenAL Soft remains a replaceable dynamic library; tools/build_openal_macos.py rebuilds its pinned source.\n'
        'See BUILDING.md and THIRD_PARTY_NOTICES.md before redistributing any compiled derivative.\n')


def package_macos(app, vulkan, output):
    """Carry only runtime loader/ICDs, not the multi-GB development SDK."""
    from package_ipa import clone_app
    clone_app(app, output)
    stage_notices(output, 'macos', vulkan)
    contents = output/'Contents'
    runtime = contents/'Resources/Vulkan'
    for name in ['libvulkan.1.dylib', 'libvulkan_kosmickrisp.dylib', 'libMoltenVK.dylib']:
        dest = runtime/'lib'/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(vulkan/'lib'/name, dest, follow_symlinks=True)
    for name in ['libkosmickrisp_icd.json', 'MoltenVK_icd.json']:
        dest = runtime/'share/vulkan/icd.d'/name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(vulkan/'share/vulkan/icd.d'/name, dest)
    plist_path = contents/'Info.plist'
    info = plistlib.loads(plist_path.read_bytes())
    info['UT3VulkanSDKPath'] = 'Vulkan'
    plist_path.write_bytes(plistlib.dumps(info))
    for library in [*(contents/'Frameworks').glob('*.dylib'), *(runtime/'lib').glob('*.dylib')]:
        run('codesign', '--force', '--sign', '-', '--timestamp=none', library)
    run('codesign', '--force', '--sign', '-', '--timestamp=none', output)
    run('codesign', '--verify', '--strict', output)


def main():
    prog = f'build_{sys.argv[1]}.sh' if len(sys.argv)>1 and sys.argv[1] in ['macos','ios'] else 'build_apple.py'
    p = argparse.ArgumentParser(prog=prog, usage='%(prog)s GAME_FOLDER [options]', description=__doc__)
    p.add_argument('target', choices=['macos', 'ios'], help=argparse.SUPPRESS)
    p.add_argument('game', type=Path, help='Steam UT3 folder containing Binaries, Engine and UTGame')
    p.add_argument('--jobs', type=int, default=8)
    p.add_argument('--sdk', type=Path, help='Existing pinned Vulkan SDK macOS folder')
    p.add_argument('--vc80-root', type=Path)
    p.add_argument('--windows-iso', type=Path)
    p.add_argument('--offline', action='store_true', help='Use cached dependencies; refuse downloads')
    p.add_argument('--build-dir', type=Path, help='Advanced: reuse a specific native build directory')
    p.add_argument('--bundle-id', default='org.ut3.port.ios', help='Advanced iOS identifier before SideStore re-signing')
    p.add_argument('--check', action='store_true', help='Check tools, dependencies and game inputs without compiling')
    args = p.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        p.error('Build on an Apple Silicon Mac with full Xcode installed and selected (not Command Line Tools alone).')
    if args.jobs < 1 or args.jobs > 32:
        p.error('--jobs must be between 1 and 32')
    for name in ['cmake', 'ninja', 'xcrun', 'curl', 'codesign']:
        if not shutil.which(name):
            p.error(f'Missing {name}. Install Xcode and run: brew install python@3.13 cmake ninja wimlib')
    game = args.game.expanduser().resolve()
    verify_game(game)
    CACHE.mkdir(parents=True, exist_ok=True)
    # Both targets share generated originals and download staging. Never race two builds.
    with (CACHE/'simple-build.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            p.error('Another Apple build is running. Wait for it to finish.')
        python = bootstrap(args.offline)
        vulkan = sdk(args)
        crt = vc80(args, game)
        run('xcrun', '--sdk', 'iphoneos' if args.target == 'ios' else 'macosx', '--show-sdk-path')
        if args.check:
            print('PASS: build prerequisites and pinned input files are ready.')
            return
        ensure_lift(python, game, crt)
        dxvk, audio, headers = renderer_and_audio(args, python, vulkan)
        build = (args.build_dir or CACHE/args.target).resolve()
        options = ['-DCMAKE_OSX_ARCHITECTURES=arm64', '-DCMAKE_BUILD_TYPE=Release',
                   '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON', '-DPython3_EXECUTABLE='+str(python),
                   '-DUT3_GENERATED='+str(ROOT/'generated'), '-DUT3_LIFT_OPT_LEVEL=1', '-DUT3_APPLE_SHA1_ROTATES=ON']
        if args.target == 'ios':
            options += ['-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_SYSROOT=iphoneos', '-DCMAKE_OSX_DEPLOYMENT_TARGET=18.0',
                        '-DBUILD_TESTING=OFF', '-DUT3_IOS_BUNDLE_ID='+args.bundle_id,
                        '-DUT3_IOS_DXVK='+str(dxvk), '-DUT3_IOS_OPENAL='+str(audio), '-DUT3_IOS_OPENAL_INCLUDE='+str(headers),
                        '-DUT3_IOS_MOLTENVK='+str(vulkan/'lib/MoltenVK.xcframework/ios-arm64/libMoltenVK.a'),
                        '-DUT3_IOS_VULKAN_INCLUDE='+str(vulkan/'include')]
        else:
            options += ['-DBUILD_TESTING=ON', '-DUT3_DXVK_LIBRARY='+str(dxvk), '-DUT3_OPENAL_LIBRARY='+str(audio),
                        '-DUT3_OPENAL_INCLUDE='+str(headers), '-DUT3_VULKAN_SDK='+str(vulkan)]
        run('cmake', '-S', ROOT, '-B', build, '-G', 'Ninja', *options)
        run('cmake', '--build', build, '--parallel', args.jobs)
        app = build/'Unreal Tournament 3.app'
        output = ROOT/'dist'/args.target
        output.mkdir(parents=True, exist_ok=True)
        if args.target == 'ios':
            stage_notices(app, 'ios', vulkan)
            run(python, '-B', ROOT/'tools/package_ipa.py', '--app', app, '--output', output/'Unreal Tournament 3.ipa')
            print('\nReady: '+str(output/'Unreal Tournament 3.ipa')+'\nSign/install it with SideStore, launch once, then put Game and cdkey.txt directly in this app’s shared files beside UserData (no extra named folder). See BUILDING.md.')
        else:
            run('ctest', '--test-dir', build, '--output-on-failure')
            with tempfile.TemporaryDirectory(prefix='ut3-selftest-', dir=build) as data:
                run(build/'ut3-runtime-selftest', '--game', game, '--data', data, '--selftest')
            package_macos(app, vulkan, output/app.name)
            print('\nReady: '+str(output/app.name)+'\nOpen the app and select your UT3 game folder.')
        (output/'build-receipt.json').write_text(json.dumps({'target':args.target,'game_input_verification':'41 exact file hashes',
            'dependencies_manifest_sha256':digest(ROOT/'config/apple-dependencies.json'),'native_build':str(build),
            'game_assets_bundled':False,'ios_signing':'SideStore re-signs the IPA' if args.target=='ios' else None},indent=2)+'\n')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('\nBuild stopped: '+str(error)+'\nFix the error above, then run the same command again; cached work is reused.', file=sys.stderr)
        sys.exit(1)
