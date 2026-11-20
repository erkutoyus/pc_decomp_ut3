# Android directory removal and simple Apple builds — 2026-11-18

The owner authorized moving all reusable files out of the root Android directory, removing that directory, and adding simple macOS/iOS build scripts. The owner selected a small IPA with game files copied separately, rather than bundled proprietary assets.

## Implementation

- Moved 41 remaining reusable source/data files to `engine/host`, `engine/runtime`, `engine/textures`, `engine/io`, `engine/dxvk`, `engine/uscript` and `engine/config`. [The removal manifest](REMOVAL_MANIFEST.md) lists every move.
- Preserved the original Android sources, retired Android-only build/launcher tools and Java/JNI-specific tests in a byte-hashed local archive before removing them. Shared native ABI/call-contract helpers are imported directly from `tools/lift_build.py`; active tools/tests no longer import the retired Android builder.
- Kept the real codecs, ZIP reader, renderer implementations, script/localization fixtures and native regression coverage. The converter's JNI adapter is guarded; its portable transaction/codec code now compiles on Darwin. Darwin descriptor-owned locks preserve same-process and cross-process exclusion and killed-writer recovery. The existing Apple DXVK path and rendering optimizations remain intact.
- Added root `build_macos.sh` and `build_ios.sh`, with a common dependency/input/lift/build orchestrator in `tools/build_apple.py`. `BUILDING.md` is the beginner-facing entry point; the main readme now describes the Apple port.
- Added exact source archive/revision and SDK binary pins in `config/apple-dependencies.json`; versions were not upgraded. The original preparation/build tools still apply the same audited overlays. Python dependencies are installed in a project venv, never into system Python.
- Existing verified CRT inputs are reused. Otherwise preparation reads a hash-pinned official Microsoft evaluation ISO using PyCdlib/wimlib to extract the exact two x86 VC80 files. No Windows process is executed. Archives, SDK, CRT and compiler outputs are cached; mismatches fail closed. Offline mode refuses dependency/Python downloads.
- The macOS artifact includes the Vulkan runtime loader, KosmicKrisp/MoltenVK ICDs and libraries with bundle-relative lookup, plus existing DXVK/OpenAL. Explicit environment overrides still work for diagnostics. No external SDK path is needed by the packaged app.
- `tools/package_ipa.py` produces an unsigned, device ARM64 IPA for SideStore to re-sign. It verifies the target platform and Payload, removes provisioning/signature material from a staging copy, preserves executable permissions, rejects external symlinks and original game/key/profile files, and emits an archive hash receipt. Original input apps are unchanged. App identity is selectable without embedding a development team/profile.
- Packaged notices accompany the app. These personal builds contain translated game code; absence of assets is not a redistribution license. No CD key, original game assets or saves are included in the IPA.

## Build commands actually exercised

From the repository root:

```sh
./build_macos.sh /Volumes/NVME512/Github/UT3 --build-dir build/apple/phase5/macos --offline
./build_ios.sh /Volumes/NVME512/Github/UT3 --build-dir build/apple/phase6/ios \
    --bundle-id org.ut3.port.ios.probe --offline
```

The advanced directory options reused the validated native object caches; both commands built new native DXVK/OpenAL dependencies using the same pins. The iOS identity option preserves this owner's installed app identity. Ordinary new-user commands need only the game folder and default to `build/apple/{macos,ios}` and `org.ut3.port.ios`. The complete 20-module original lift was verified/reused, not regenerated during this cleanup. A brand-new full lift/build was not repeated; do not describe this as a fresh end-to-end code-generation test.

Outputs are `dist/macos/Unreal Tournament 3.app` and `dist/ios/Unreal Tournament 3.ipa`. The IPA is about **56 MiB** before game data. Both require the owner's original files at runtime; iOS uses Finder file sharing as documented in `BUILDING.md`.

The original direct build commands and exact per-stage compiler/tool invocations remain in `build/apple/cleanup/simple-{macos,ios}-build.log`. Additional package/closure/device receipts live beside them and in `dist/`. These are private local artifacts, not published game inputs.

## Results

| Check | Actual result |
| --- | --- |
| macOS one-command build | PASS: app linked, 15/15 CTests passed, original headless runtime self-test passed, standalone app signed/verified |
| iOS one-command build with root Android tree absent | PASS: device ARM64 app linked; unsigned IPA produced and archive CRC/Payload/platform verified |
| Portable Python regression | PASS: 19 tests covering IPA safety/layout, rotate equivalence, frame analysis, native same-unit calls and coverage inventory |
| Actual texture codecs/package/lock fixture on M4 | PASS: bounded LZO malformed/truncated inputs, DXT mips, real ETC2/ASTC encode/decode, live same/cross-process exclusion, killed-writer recovery |
| M4 standalone packaged D3D9 | PASS with external loader/driver/layer overrides unset; exact GPU fixture, 720p/1080p resets/Present and native shutdown status 0 |
| Source/dependency closure | PASS: macOS 2,101 compile commands, iOS 2,083, each renderer 143 and OpenAL 104; Ninja dependencies/commands, Mach-O imports and symbols checked with no root Android/SDK/NDK/JNI/system dependencies |
| Fresh source dependency retrieval | All five archive hashes and complete source assembly/shared overlay preparation validated against 954 pins. GitLab's non-archive response was rejected; the maintainer's mirror matches the original pin. |
| CRT extraction command | PASS: both exact pinned files extracted from the existing authenticated WIM using the same flat extraction arguments; SHA-256 matches. Full ISO download/re-extraction was not repeated. |
| AppKit window/input and early shutdown | PASS: early quit; window/input fixture through LaunchServices with a temporary original-binary fixture. Explicit PASS markers confirm drawable sizing, keyboard, mouse, focus release, XInput and ownership teardown. Initial foreground/external-path attempts failed as described below. |
| M4 real offline maps / repeated lifecycle | PASS: 85-second Morbias and Deck sessions, each with original LoadMap/Bringing World/START MATCH logs, native accepted Presents and nonzero CoreAudio output, zero observed game audio errors/nonfinite samples. Each quit via NSRunningApplication/AppKit with exit 0 and no runtime worker outstanding. These are automated spectator sessions, not a human controller playtest. |
| Device installation/testing | Initially blocked: CoreDevice reports the iPhone unavailable. Payload was re-signed with the existing development profile for local device validation; that is separate from SideStore signing. Awaiting reconnection. |

## Failed attempts and limits

The first direct AppKit shell fixture did not acquire foreground focus and logged FAIL while returning zero; subsequent validation must inspect PASS markers, not only process status. This failed attempt is preserved in `shell-validation.log`. LaunchServices with redirected external-volume logs initially returned -10810; a repeat was sampled waiting in `mkdirat` before runtime initialization. That diagnostic process was stopped. The same packaged app then passed via LaunchServices with its data/logs and a private original-binary fixture under `/private/tmp`, without a code change. `shell-temporary-console.log` contains the explicit PASS markers. The temporary binary fixture was removed after saving its log.

The first preflight tried installing missing pinned Python packages inside the restricted network sandbox and failed; installation succeeded with network access. Offline handling was then corrected to refuse missing Python packages without accessing the network. An initial expanded Python invocation imported a Windows-only compiler fixture through `LOCALAPPDATA`; the preserved same-unit fixture now has a native host compile/run branch. Coverage inventory tests then exposed Darwin's `/var` versus `/private/var` path normalization; resolving lifted paths consistently fixed all six failures. These were not game behavior changes.

The full historical test directory is not a platform-independent suite: some original oracles require Windows/MSVC, GLES/device contexts or separately prepared game fixtures. Those are not counted as passing Apple regressions. Android-only launcher/Java tests were archived rather than asserted to work without their retired implementation.

Existing guest DLL-detach HeapFree diagnostics and iPhone OpenAL/EAX setup errors remain recorded in the phase reports. Startup/package/pipeline hitches are not fixed by this layout/build cleanup. The iOS minimum deployment setting is not proof of older-device compatibility. No SideStore signing/account flow, battery/thermal improvement or public redistribution clearance is asserted by IPA creation.

Every archived original file hash was checked, then the temporary Android holding directories were deleted. The root `android/` directory no longer exists. The local Android reference archive is retained; no original game files or installed app data are deleted by the cleanup/build scripts. Current M4 map and iPhone continuation results will be appended here as verification completes.

## Default-command and SideStore continuation — 2026-11-19

The exact beginner commands without advanced arguments subsequently completed successfully: `./build_macos.sh /Volumes/NVME512/Github/UT3` and `./build_ios.sh /Volumes/NVME512/Github/UT3`. Default native trees compiled in `build/apple/macos` and `build/apple/ios`; the complete existing 20-module lift was reused. The default Mac command passed 15 native tests plus the original runtime self-test and packaged its app. The default iOS command produced the device IPA with `org.ut3.port.ios` before SideStore re-signing. Logs are `exact-{macos,ios}-command.log`.

The owner installed that IPA through SideStore, then requested a clearer first-launch data layout and remembered Mac selection. Build 9 implements those changes and has been observed installed through SideStore. Current locations, 16/16 native and 19 Python results, two actual Mac default-path relaunch checks and pending physical iPhone launch verification are recorded in [DATA_LOCATIONS.md](DATA_LOCATIONS.md). The root Android directory remains absent; all 41 moved destinations and archived original hashes were reverified.
