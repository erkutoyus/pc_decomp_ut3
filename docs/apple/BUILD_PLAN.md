# Apple build plan

## Current baseline

The Mac mini reports Apple M4, 32 GB RAM, `arm64`, macOS 27.2 (`26B123`), Xcode 27.2 (`27B52`), macOS/iPhoneOS SDK 27.2, Apple Clang 21.0.0 (`clang-2100.4.1.1`), CMake 4.4.4, Ninja 1.13.2, and 16 KiB pages. Xcode emitted sandbox cache and FSEvents warnings while supplying the SDK paths. [Phase 0 commands and results](TEST_MATRIX.md) distinguish the VM probe from the future game build.

## Stages and receipts

1. **Original inputs.** Point the verifier at the supplied installation. Use an isolated Python environment and pinned wheels. Locate the two exact VC80 x86 files and verify them against `config/modules.json`. The verifier accepts `--root` and `--verify`. The lifter accepts local game and CRT paths without modifying either manifest.
2. **Generate C and manifests.** Run `tools/lift_ut3.py` for the complete module set. It writes prepared binaries to `generated/input`, source chunks and `functions.h` with reports per module, and merged `dispatch.c` and `modules.inc`. Capture tool revisions, Python/platform identity, source paths or aliases, PE hashes, reports, rejected/trap counts and generated artifact hashes. A Windows-generated tree is a fallback while local build-tool portability is tested. Authenticate and validate every file used by the native compiler, and check exact image/dispatch completeness and absence of stale generated artifacts.
3. **Native compile and link.** CMake drives Apple Clang and Ninja from an explicit list of host sources and a generated manifest. The Apple preparer reuses the x87 slot pass, native same-unit rewrites and wrapper inventory. Original wrapped bodies use `__real_` symbols, and Mach-O aliases route public symbols to the matching wrappers. The headless build retains `-fno-strict-aliasing`, `-fwrapv`, `-ffp-contract=off`, the constant guest base and the separate-storage compiler profile for lifted code.
4. **Run the CLI self-test.** The existing command-line driver accepts `--game`, `--data` and `--selftest`. Supply a fresh data directory and the verified Steam directory. The headless build needs the real modules, imports, guest VM, DLL/TLS attach and feature init. It does not need to create a D3D device or physical audio stream. The Android builder cannot produce this target using its command-line mode, because it still stages Android dependencies and links Android system libraries.
5. **Package an app after CLI validation.** Add AppKit, GameController, QuartzCore and graphics/audio dependencies as their phases land. Provide native signed Mach-O and platform-appropriate framework dependencies, package the chosen Vulkan backend with explicit loader resolution, and verify install names, rpaths and signing. Keep user data in Application Support and select a separate game root.
6. **Build iOS separately.** Use an iPhoneOS ARM64 toolchain and device signing/provisioning. Build the shared engine and iOS slices from source with their own receipts, link UIKit and iOS transport, and verify framework embedding/linking on hardware. Copy owner-provided data into the app container through an appropriate import flow. The signed VM feasibility probe after Phase 1 precedes this full build.

## Commands and expected entry point

These input commands use the current interfaces. The isolated environment and verifier must be confirmed after the dependency blocker is resolved.

```sh
python3.13 -m venv /tmp/ut3-build-venv
/tmp/ut3-build-venv/bin/python -m pip install -r requirements.txt
/tmp/ut3-build-venv/bin/python tools/inspect_inputs.py --root "$PWD/../UT3" --verify
```

The Phase 1 CLI accepts the following commands. `UT3_VC80_ROOT` denotes the directory containing the exact DLLs from the [dependency audit](DEPENDENCIES.md). The lifter generates all 20 modules.

```sh
/tmp/ut3-build-venv/bin/python tools/lift_ut3.py --game-root "$PWD/../UT3" --vc80-root "$UT3_VC80_ROOT"
cmake -S . -B build/apple/macos -G Ninja -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE=/tmp/ut3-build-venv/bin/python
cmake --build build/apple/macos --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
file build/apple/macos/ut3-runtime-selftest
otool -L build/apple/macos/ut3-runtime-selftest
ut3_test_data=$(mktemp -d /tmp/ut3-selftest.XXXXXX)
build/apple/macos/ut3-runtime-selftest --game "$PWD/../UT3" --data "$ut3_test_data" --selftest >"$ut3_test_data/console.log" 2>&1
ut3_test_status=$?
cat "$ut3_test_data/console.log"
test "$ut3_test_status" -eq 0 && rg -F '[selftest] PE binding, DLL/TLS startup, guest heap and static entry lookup PASS' "$ut3_test_data/ut3.log"
```

Run the existing `build_uscript.py` on an authorized Windows development setup if a later UI build requires it. Regen of post-FX bytecode and Windows differential oracles also remains separate. A full Mac-native production pipeline is pending verification.

## Phase 1 target scope

`ut3-runtime-selftest` requires explicit game and writable data paths and enters the original `ut3_game_main(..., selftest=1)` path. It uses the real PE loader, shims, lifted module bodies and existing native wrappers. Apple Clang compiles the lift at `-O1` by default with the x87 slot pass and guest-state separation. The first build uses the full register/flags call protocol. The optional `UT3_CALL_PROTOCOL` and `UT3_X87_LOCALS` CMake inputs use the existing passes and need separate validation. The headless source list excludes renderer, device audio and network implementations. Missing guest imports retain the loader's trap path.

## Phase 2 AppKit bundle

Build from the same configured tree and launch in the graphical login session.

```sh
cmake --build build/apple/macos --target ut3-macos --parallel 8
open -n "$PWD/build/apple/macos/Unreal Tournament 3.app"
```

The app offers a game folder picker. It also accepts `--game PATH` for automated launches and `--data PATH` to override the default `~/Library/Application Support/Unreal Tournament 3` directory. The shell refuses a data directory within the selected game tree. It writes `shell.log` and the existing engine writes `ut3.log` and `ut3-crash.txt` under the user-data directory. The bundle uses the same generated objects and runtime entry as the command-line self-test.

## Phase 3 graphics build and capture

Use the LunarG macOS Vulkan SDK and pinned DXVK tree recorded in [dependencies](DEPENDENCIES.md). Keep the checkout and its submodules outside the generated DXVK overlay directory. The local build used these commands.

```sh
ut3_sdk="$PWD/build/apple/phase3-inputs/VulkanSDK/macOS"
ut3_dxvk_src="$PWD/build/apple/phase3-inputs/dxvk-upstream"
ut3_meson="$PWD/build/apple/phase3-inputs/meson-venv/bin/meson"

build/apple/venv/bin/python -uB tools/build_dxvk_macos.py \
    --source "$ut3_dxvk_src" --sdk "$ut3_sdk" --meson "$ut3_meson"
cmake -S . -B build/apple/macos -G Ninja -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE="$PWD/build/apple/venv/bin/python" \
    -DUT3_DXVK_LIBRARY="$PWD/build/apple/dxvk/src/d3d9/libdxvk_d3d9.dylib"
cmake --build build/apple/macos --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
```

The bundle stages the ARM64 DXVK dylib in Contents/Frameworks and generates Contents/Resources/UT3.icns from the supplied 1024-pixel PNG. The SDK loader and ICDs remain external in this development build. Omitting `UT3_DXVK_LIBRARY` builds the headless and Phase 2 validation paths.

Validate both ICDs from a graphical login in this order. The standalone probe compares the swapchain image against the requested clear color before presenting it.

```sh
xcrun clang++ -arch arm64 -std=c++17 -O2 -fobjc-arc tests/test_vulkan_wsi.mm \
    -I"$ut3_sdk/include" -L"$ut3_sdk/lib" -Wl,-rpath,"$ut3_sdk/lib" \
    -framework AppKit -framework Metal -framework QuartzCore -lvulkan \
    -o build/apple/test-vulkan-wsi
ut3_app="$PWD/build/apple/macos/Unreal Tournament 3.app/Contents/MacOS/Unreal Tournament 3"
export VK_LAYER_PATH="$ut3_sdk/share/vulkan/explicit_layer.d"
export VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation
export UT3_VULKAN_LOADER="$ut3_sdk/lib/libvulkan.1.dylib"
for ut3_icd in libkosmickrisp MoltenVK; do
    export VK_DRIVER_FILES="$ut3_sdk/share/vulkan/icd.d/${ut3_icd}_icd.json"
    ut3_run=$(mktemp -d "$PWD/build/apple/${ut3_icd}.XXXXXX")
    build/apple/test-vulkan-wsi "$ut3_run/clear.ppm" >"$ut3_run/wsi.log" 2>&1
    "$ut3_app" --game "$PWD/../UT3" --data "$ut3_run" --validate-d3d9 >"$ut3_run/d3d9.log" 2>&1
done

export VK_DRIVER_FILES="$ut3_sdk/share/vulkan/icd.d/libkosmickrisp_icd.json"
ut3_capture=$(mktemp -d "$PWD/build/apple/ut3-frame.XXXXXX")
"$ut3_app" --game "$PWD/../UT3" --data "$ut3_capture" --capture-first-frame >"$ut3_capture/console.log" 2>&1
```

The capture run continues in the guest after writing `ut3-first-frame.ppm`. The test harness observed presentation for eight seconds after capture and then sent SIGTERM. The game log is under `Documents/My Games/Unreal Tournament 3/UTGame/Logs/Launch.log` in the run directory. The shell also records the validation result and startup state in `shell.log`. Each backend should use a fresh run directory to isolate cold logs and caches.

## Phase 4 CoreAudio and playtest

Fetch OpenAL Soft from the pinned public revision and pass its archive to the Apple builder. The builder checks the repository archive and callback meter hashes and leaves a library receipt in its output directory. Xcode 27.2 required an override for its stricter function-effects diagnostic when compiling the pinned CoreAudio callbacks.

```sh
ut3_openal_rev=b2c48f7718ef3fcf67921a8b6534c4914e328970
ut3_audio_stage="$PWD/build/apple/phase4-inputs"
mkdir -p "$ut3_audio_stage"
curl -fL "https://codeload.github.com/kcat/openal-soft/tar.gz/$ut3_openal_rev" \
    -o "$ut3_audio_stage/openal-soft.tar.gz"
build/apple/venv/bin/python -uB tools/build_openal_macos.py \
    --archive "$ut3_audio_stage/openal-soft.tar.gz" --build build/apple/openal-meter
cmake -S . -B build/apple/macos \
    -DUT3_DXVK_LIBRARY="$PWD/build/apple/dxvk/src/d3d9/libdxvk_d3d9.dylib" \
    -DUT3_OPENAL_LIBRARY="$PWD/build/apple/openal-meter/libopenal.1.25.2.dylib" \
    -DUT3_OPENAL_INCLUDE="$PWD/build/apple/openal-meter-source-b2c48f7718ef/include"
cmake --build build/apple/macos --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
```

Launch the app in a graphical login with the external Vulkan SDK. Its ordinary launch opens the UT3 front end at the resolution in the guest's saved video settings. Use an owner-provided `cdkey.txt` as described in [CDKEY_FILE.md](CDKEY_FILE.md), or enter the original key directly in UT3, then choose Play Offline. The state directory must remain stable for the protected record. macOS can ask the user to authorize Keychain access when an ad hoc build changes. The capture-only diagnostic still uses its Phase 3 command line and disables sound.

```sh
ut3_sdk="$PWD/build/apple/phase3-inputs/VulkanSDK/macOS"
ut3_app="$PWD/build/apple/macos/Unreal Tournament 3.app/Contents/MacOS/Unreal Tournament 3"
ut3_data="$PWD/build/apple/phase4-playtest"
mkdir -p "$ut3_data"
export VK_DRIVER_FILES="$ut3_sdk/share/vulkan/icd.d/libkosmickrisp_icd.json"
export UT3_VULKAN_LOADER="$ut3_sdk/lib/libvulkan.1.dylib"
export UT3_AUDIO_METRICS=1
export ALSOFT_DRIVERS=core
"$ut3_app" --game "$PWD/../UT3" --data "$ut3_data" >"$ut3_data/interactive-audio.log" 2>&1
```

For a short repeat with the same profile, use the original UT3 map URL as the launch input. Launch the front end and the repeat serially when using one data directory. Command-Q and Close Window request UE3's orderly shutdown. Drop `UT3_AUDIO_METRICS` outside runs that need the callback meter.

```sh
UT3_COMMAND_LINE='"C:\Games\UT3\Binaries\UT3.exe" DM-Morbias?NumPlay=3?TimeLimit=1?GoalScore=3?QuickStart=1?ForceRespawn=1 -nosplash -nomovie -forcelogflush -onethread -ResX=960 -ResY=540' \
    "$ut3_app" --game "$PWD/../UT3" --data "$ut3_data" >"$ut3_data/repeat-match.log" 2>&1
```

The playtest launcher uses `-nomovie` for the current Apple build. Bink presentation and DirectSound hardware output have separate validation work. The launcher reads the player's Steam installation in place and keeps the original data outside the app bundle.

### Video modes and frame timing

Rebuild DXVK and the app using the Phase 3 commands after changing the Apple WSI or the pipeline-cache overlay. Use `--validate-d3d9` with the Vulkan validation layer to exercise mode enumeration, back-buffer reset and presentation. To check video setting persistence, launch Morbias with a fresh data directory and omit the explicit resolution and log-flush flags. Select **Settings → Video → Screen Resolution**, apply and accept the change, quit with Command-Q, and repeat the same command with the same data directory.

```sh
ut3_data="$PWD/build/apple/phase4-perf/game-modes"
mkdir -p "$ut3_data"
UT3_COMMAND_LINE='"C:\Games\UT3\Binaries\UT3.exe" DM-Morbias?NumPlay=3?QuickStart=1 -nosplash -nomovie -onethread' \
    "$ut3_app" --game "$PWD/../UT3" --data "$ut3_data" >"$ut3_data/console.log" 2>&1
```

The Apple bridge reports elapsed time between accepted Vulkan presents, including counts over 25, 50 and 100 ms and the longest gap in each reporting interval. These measure submission cadence. Use Metal traces to measure completion and display timing. During profiling use a separate data directory for each run so that the same initial configuration and pipeline cache can be reproduced.

To collect individual frame gaps, set `UT3_FRAME_TRACE` to a writable CSV path. It includes the frame number, elapsed time from the first accepted present, and the gap since the preceding accepted present in milliseconds. The same run emits Instruments Points of Interest for the first present and gaps above 25 ms. This example starts an offline Deck match with a bot spectator view at 1080p.

```sh
ut3_run="$PWD/build/apple/phase4-stutter"
mkdir -p "$ut3_run/repro-profile"
xcrun xctrace record --template 'Time Profiler' --time-limit 36s \
    --output "$ut3_run/repro.trace" --target-stdout "$ut3_run/repro-console.log" \
    --env "UT3_FRAME_TRACE=$ut3_run/repro-frames.csv" \
    --env 'UT3_COMMAND_LINE="C:\Games\UT3\Binaries\UT3.exe" DM-Deck?NumPlay=8?SpectatorOnly=1?QuickStart=1?TimeLimit=0 -nosplash -nomovie -onethread -fixedseed -ResX=1920 -ResY=1080' \
    --launch -- "$ut3_app" --game "$PWD/../UT3" --data "$ut3_run/repro-profile"
xcrun xctrace export --input "$ut3_run/repro.trace" \
    --xpath '/trace-toc/run/data/table[@schema="time-profile" or @schema="PointsOfInterestEvents"]' \
    --output "$ut3_run/repro.xml"
```

For a comparison without Instruments, run the same command line directly and copy the same starting DXVK state and Vulkan pipeline cache files into each fresh data directory. Set `UT3_CRT_PRINTF=0` to use the original VC80 formatter while retaining the other ARM64 optimizations. Set `UT3_CRT_PRINTF=verify` in a separate correctness run to compare supported calls with the live VC80 implementation. The verification path runs both implementations.

### Finder launch

The development bundle records `UT3_VULKAN_SDK` in its Info.plist. It defaults to the local SDK installed in Phase 3. Finder can launch the app and accept the normal folder picker without Terminal environment variables. The app checks the loader before starting the guest. To use a different SDK installation, configure CMake with `-DUT3_VULKAN_SDK=/path/to/sdk/macOS`. Diagnostic launches can still supply their own Vulkan loader and ICD through the environment.

## Phase 5 clean Apple build and regression

Run from the repository root. The Phase 5 build uses independent output directories and the existing pinned source archives. The commands below unset Android and Java toolchain configuration. Apple Clang, CMake, Ninja, Python and the pinned macOS Vulkan SDK remain required.

```sh
ut3_phase5="$PWD/build/apple/phase5"
ut3_sdk="$PWD/build/apple/phase3-inputs/VulkanSDK/macOS"
ut3_meson="$PWD/build/apple/phase3-inputs/meson-venv/bin/meson"
mkdir -p "$ut3_phase5"
unset ANDROID_HOME ANDROID_SDK_ROOT ANDROID_NDK_HOME JAVA_HOME
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"

build/apple/venv/bin/python -uB tools/build_dxvk_macos.py     --source "$PWD/build/apple/phase3-inputs/dxvk-upstream"     --sdk "$ut3_sdk" --meson "$ut3_meson" --build "$ut3_phase5/dxvk" --jobs 8
build/apple/venv/bin/python -uB tools/build_openal_macos.py     --archive build/apple/phase4-inputs/openal-soft.tar.gz --build "$ut3_phase5/openal"
cmake -S . -B "$ut3_phase5/macos" -G Ninja     -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_BUILD_TYPE=Release     -DCMAKE_EXPORT_COMPILE_COMMANDS=ON     -DPython3_EXECUTABLE="$PWD/build/apple/venv/bin/python"     -DUT3_DXVK_LIBRARY="$ut3_phase5/dxvk/src/d3d9/libdxvk_d3d9.dylib"     -DUT3_OPENAL_LIBRARY="$ut3_phase5/openal/libopenal.1.25.2.dylib"     -DUT3_OPENAL_INCLUDE="$ut3_phase5/openal-source-b2c48f7718ef/include"
cmake --build "$ut3_phase5/macos" --parallel 8
ctest --test-dir "$ut3_phase5/macos" --output-on-failure
python3 -B tools/check_apple_dependencies.py     --build "$ut3_phase5/macos" --dxvk-build "$ut3_phase5/dxvk" --openal-build "$ut3_phase5/openal"

mkdir -p "$ut3_phase5/headless"
"$ut3_phase5/macos/ut3-runtime-selftest"     --game "$PWD/../UT3" --data "$ut3_phase5/headless" --selftest
UT3_TEST_GAME_ROOT="$PWD/../UT3" UT3_VC80_ROOT="$PWD/build/apple/vc80"     build/apple/venv/bin/python -B -m unittest tests.test_inspect_inputs tests.test_lift_inputs
```

For shell and graphics checks, launch the new app executable with a separate data directory per diagnostic and use `--validate-shell`, `--validate-early-quit`, and `--validate-d3d9`. The D3D9 run uses `VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation` and `VK_LAYER_PATH="$ut3_sdk/share/vulkan/explicit_layer.d"`.

For the gameplay repeat, use the same isolated profile serially. Command-Q ends the first run. Close Window ends the second. Capture the shell exit status and preserve each run's logs before restarting.

```sh
ut3_app="$ut3_phase5/macos/Unreal Tournament 3.app/Contents/MacOS/Unreal Tournament 3"
mkdir -p "$ut3_phase5/repeat"
UT3_AUDIO_METRICS=1 ALSOFT_DRIVERS=core UT3_COMMAND_LINE='"C:\Games\UT3\Binaries\UT3.exe" DM-Morbias?NumPlay=3?TimeLimit=1?GoalScore=3?QuickStart=1?ForceRespawn=1 -nosplash -nomovie -onethread -ResX=1920 -ResY=1080'     "$ut3_app" --game "$PWD/../UT3" --data "$ut3_phase5/repeat"     >"$ut3_phase5/repeat1-console.log" 2>&1
printf 'Exit status %d\n' "$?" >"$ut3_phase5/repeat1-status.txt"

UT3_AUDIO_METRICS=1 ALSOFT_DRIVERS=core UT3_COMMAND_LINE='"C:\Games\UT3\Binaries\UT3.exe" DM-Deck?NumPlay=3?TimeLimit=1?GoalScore=3?QuickStart=1?ForceRespawn=1 -nosplash -nomovie -onethread -ResX=1920 -ResY=1080'     "$ut3_app" --game "$PWD/../UT3" --data "$ut3_phase5/repeat"     >"$ut3_phase5/repeat2-console.log" 2>&1
printf 'Exit status %d\n' "$?" >"$ut3_phase5/repeat2-status.txt"
```


## Phase 6 iOS device diagnostics (2026-11-17)

Status and failures: [PHASE6_STATUS.md](PHASE6_STATUS.md). These commands build and test a development diagnostic app, not a playable iOS port. Keep the Phase 5 macOS build directory separate. Run dependent operations sequentially. Commands below use the existing locally verified inputs and pinned Python/Meson environments. `UT3_DEVICE` and `UT3_TEAM` are the owner's paired device identifier and development team; `UT3_SIGN_IDENTITY` is their existing Apple Development certificate name or hash. Do not commit provisioning material.

Build the small reproducible VM/provisioning scaffold (the original successful run used equivalent sources in `build/apple/phase6/probe-source`):

```sh
cmake -S platform/apple/ios/probe -B build/apple/phase6/probe -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 -DUT3_IOS_DEVELOPMENT_TEAM="$UT3_TEAM"
xcodebuild -project build/apple/phase6/probe/UT3DeviceProbe.xcodeproj \
  -scheme ut3-ios-probe -configuration Release -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates
```

Use a fresh scaffold build directory if an existing cache points to the old temporary source. Install and run this small app with the devicectl commands below before the full runtime, to check VM layout on the actual device.

```sh
build/apple/venv/bin/python -uB tools/build_dxvk_ios.py \
  --source "$PWD/build/apple/phase3-inputs/dxvk-upstream" \
  --sdk "$PWD/build/apple/phase3-inputs/VulkanSDK/macOS" \
  --meson "$PWD/build/apple/phase3-inputs/meson-venv/bin/meson" \
  --build "$PWD/build/apple/phase6/dxvk-portability"
cmake -S . -B build/apple/phase6/ios -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DPython3_EXECUTABLE="$PWD/build/apple/venv/bin/python" \
  -DUT3_IOS_GUEST_BASE=0x7000000000ull \
  -DUT3_IOS_BUNDLE_ID=org.ut3.port.ios.probe \
  -DUT3_IOS_MOLTENVK="$PWD/build/apple/phase3-inputs/VulkanSDK/macOS/lib/MoltenVK.xcframework/ios-arm64/libMoltenVK.a" \
  -DUT3_IOS_VULKAN_INCLUDE="$PWD/build/apple/phase3-inputs/VulkanSDK/macOS/include" \
  -DUT3_IOS_DXVK="$PWD/build/apple/phase6/dxvk-portability/src/d3d9/libdxvk_d3d9.dylib"
cmake --build build/apple/phase6/ios --parallel 8
build/apple/venv/bin/python -B tools/package_ios.py \
  --app 'build/apple/phase6/ios/Unreal Tournament 3.app' \
  --provisioned-app build/apple/phase6/probe/Release-iphoneos/ut3-ios-probe.app \
  --identity "$UT3_SIGN_IDENTITY" \
  --output 'build/apple/phase6/d3d9-device/Unreal Tournament 3.app'
xcrun devicectl device install app --device "$UT3_DEVICE" --timeout 50 \
  'build/apple/phase6/d3d9-device/Unreal Tournament 3.app'
xcrun devicectl device copy to --device "$UT3_DEVICE" \
  --domain-type appDataContainer --domain-identifier org.ut3.port.ios.probe \
  --source ../UT3/Binaries --destination Documents/Game/Binaries
xcrun devicectl device process launch --device "$UT3_DEVICE" \
  --terminate-existing --console org.ut3.port.ios.probe
```

For the runtime-only check, append `-- --selftest`: it executes `ut3_validate_startup`, hence `ut3_game_main(..., selftest=1)`, and retains its result on screen. A normal iPhone launch now starts the game; optional `Documents/cdkey.txt` is validated by the original game routine. See [CDKEY_FILE.md](CDKEY_FILE.md). Repeat launch in a separate terminal as needed: `--console` stays attached until the app exits or is replaced. For GPU diagnostics append `-- --validate-vulkan` or `-- --validate-d3d9`. Add `--dynamic-samplers` to the D3D9 arguments for dynamic-branch coverage, or use `-- --validate-game --exit-after-frame` for a real UT3 frame and engine-thread exit request. The Vulkan branch does not need game inputs; D3D9 first runs the real self-test then the existing COM fixture. The initial D3D9 fixture failed device creation. The current iOS builder adds the explicit D3D9 compatibility overlay; exact ARGB fixture runs now pass on device. See [D3D9_PORTABILITY.md](D3D9_PORTABILITY.md) for the real-game validation follow-up and additional launch arguments.

Preserve stdout with shell redirection; copy sandbox logs before a later launch overwrites them:

```sh
xcrun devicectl device copy from --device "$UT3_DEVICE" \
  --domain-type appDataContainer --domain-identifier org.ut3.port.ios.probe \
  --source Documents/UserData --destination build/apple/phase6/captured-userdata
cmake --build build/apple/phase5/macos --parallel 8
ctest --test-dir build/apple/phase5/macos --output-on-failure
```

Signing requires existing keychain access. Physical-device commands require CoreDevice access; macOS networking tests need local loopback bind permission. A sandbox denial must not be interpreted as a game behavior regression. No proprietary game content is embedded in the app/source. App updates retain the probe's sandbox; do not reuse another existing UT3 application's identifier without owner consent.

For a real launch also copy `../UT3/Engine` to `Documents/Game/Engine` and `../UT3/UTGame` to `Documents/Game/UTGame`, using the same app-container copy command as Binaries. Wait for these transfers to complete before replacing the app. For exact device validation add `--environment-variables '{"MTL_DEBUG_LAYER":"1","MTL_SHADER_VALIDATION":"1"}'` before the bundle identifier. Keep first-frame diagnostics separate from gameplay/audio validation: the diagnostic command line explicitly uses `-nosound` and preserves the original CD-key screen.


## File-based CD key support (2026-11-18)

Completed on macOS and the physical iPhone: the owner-provided `cdkey.txt` passes the original game validator and reaches Login. A synthetic invalid key is rejected. The Mac file-mode backend prevents legacy Keychain authentication UI while retaining records and restoring the previous interaction setting. Native input/audio/gameplay remain Phase 6 work; Phase 7 is not started. File locations, preserved ABI/validation, exact tests, remaining limitations and evidence are in [CDKEY_FILE.md](CDKEY_FILE.md).


## Phase 6 gameplay continuation (2026-11-18)

The native UIKit keyboard, GameController/XInput bridge and pinned OpenAL Soft RemoteIO backend are implemented. The owner verified keyboard typing/deletion/Done, clear sound and a full offline match with GameSir X5 Lite. The owner also verified correct touch selection, keyboard operation, one-second Keyboard button disappearance, and audible sound/controller recovery after restoring the app. Explicit foreground audio-session/device recovery is implemented; external route changes, interruptions and memory pressure remain unverified. Earlier pending statements above describe previous checkpoints. [Current evidence, exact commands, source boundaries and unresolved issues](IOS_GAMEPLAY.md). Phase 7 has not started.


## iOS resolution and icon continuation (2026-11-18)

The ordinary launcher no longer forces 640x480 over the saved UE3 resolution. The updated phone launch uses its existing 1280x720 setting; successful iOS back-buffer changes update the full-surface cursor clip. The supplied icon now compiles into the signed iOS bundle. All 12 native host tests pass. The owner verified touch coverage at 1920x1080, a visible Home Screen icon and, after rechecking an initial contrary report, saved resolution persistence. No additional runtime change was required. [Diagnosis, exact commands, changed files and device evidence](IOS_RESOLUTION.md). Phase 7 has not started.

## Phase 7 iPhone performance update

See [PHASE7_STATUS.md](PHASE7_STATUS.md) for the 720p/60 FPS target, exact commands, pinned dependency continuity, measured results, optional experiments and remaining failures.

## Simple builds and final directory cleanup

The owner-authorized root Android removal and two-command Apple build path are documented in [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md). Use [BUILDING.md](../../BUILDING.md) for current beginner instructions; older Android-reference/build statements above describe earlier checkpoints.

## Visible data folder update — 2026-11-19

Current macOS/iOS paths, safe legacy migration, remembered Mac installation, build 9 tests and SideStore verification status are in [DATA_LOCATIONS.md](DATA_LOCATIONS.md). Older Documents/Game and Application Support instructions above describe earlier builds.
