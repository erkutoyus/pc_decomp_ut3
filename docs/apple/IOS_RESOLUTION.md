# Phase 6 resolution persistence, touch bounds and icon — 2026-11-18

## Report and diagnosis

The owner uses the original game's offline-profile workaround: copy `Player.ue3profile` to a personally named `.ue3profile` under `UTGame/SaveData`, then use that profile name in offline Login without a password. The owner confirmed that this profile saves settings. The port does not create, rename or replace these files, and does not change authentication or original profile validation.

Resolution had an independent launcher defect: every ordinary iOS launch appended `-ResX=640 -ResY=480`, overriding UE3's saved resolution. The copied phone `UTEngine.ini` contains `ResX=1280` and `ResY=720`. Removing the forced command-line dimensions allows the original engine to load these settings. The default Vulkan display-mode fallback remains 640x480 until device creation; it does not replace the back-buffer parameters supplied by UE3. Explicit diagnostic command-line overrides are still supported.

Touch already used the active D3D9 back-buffer dimensions and correct aspect-ratio mapping, but the shared input clamp can retain an old full-screen ClipCursor rectangle after a larger back buffer is created. The iOS successful CreateDevice/Reset path now publishes its input surface size and updates a clip equal to the entire previous surface to the new full surface. Deliberately smaller guest clip rectangles remain intact. Failed resets do not publish a new input surface. Ordinary `void_input_set_screen_size` retains its previous behavior; Android and macOS retain their prior device-parameter/input behavior. The UIKit touch path no longer repeatedly writes the desktop size.

The iOS bundle had no icon catalog. `tools/build_ios_icon.py` compiles the supplied `icons/AppIcon1024.png` through Xcode actool for iphoneos, producing `Assets.car`, compatibility PNGs and generated primary-icon metadata. The native CMake target invokes this before the separate signing/package step. No downloaded art, generated replacement icon or game assets were added.

## Actual verification

- Native iOS build and signing/package verification: PASS. Actool emitted the iPhone/iPad icon metadata and a 3,570,584-byte Assets.car. The provided 1024px PNG was visually inspected. Development install succeeded under the existing bundle identifier, preserving Documents/profile/configuration.
- Real iPhone launch: **1280x720 back buffer and input surface**, accepted Vulkan Present. The first touch reports `clip=0,0..1280,720`. This confirms reading the existing saved resolution without changing its INI or profile. Evidence: `build/apple/phase6/resolution/device-launch.log`.
- Native host regressions: **12/12 PASS**, 8.05 s, `macos-tests.log`. The production input fixture now covers full-screen clip expansion 640x480→1920x1080, reaching (1910,1070), preservation of a custom clip, shrink and invalid-size handling. Existing text and input checks remain. Both macOS and iOS builds succeeded.
- Owner acceptance: confirmed touch reaches bottom/right buttons at 1920x1080 and the app icon is visible. The owner initially reported resolution returning to 1280x720, then rechecked and explicitly confirmed that the resolution setting is saved. Persistence is therefore owner-verified; no additional runtime or profile change was made in response to the initial failure report. These are physical user checks, separate from the logged startup and host tests.

Local evidence is under `build/apple/phase6/resolution/`: `before-userdata/`, `copy-before.log`, `ios-build.log`, `ios-ready-build.log`, `macos-build.log`, `macos-tests.log`, `package.log`, `install.log`, `device-launch.log`, and the signed `device/Unreal Tournament 3.app`.

## Changes and commands

Changed `platform/apple/ios/Application.m` (ordinary launch arguments), `platform/apple/ios/GameView.m` (extent diagnostics and input-size ownership), `engine/host/input.{c,h}` (explicit surface-resize operation), `engine/dxvk/bridge.cpp` (successful iOS back-buffer publication), `tests/test_apple_text.c` (resize/clip regression), `platform/apple/ios/CMakeLists.txt` and new `tools/build_ios_icon.py` (asset compilation). Documentation links this report. No dependency revision, generated guest function, guest ABI, profile content or performance optimization was changed.

```sh
cmake --build build/apple/phase6/ios --parallel 8
cmake --build build/apple/phase5/macos --parallel 8
ctest --test-dir build/apple/phase5/macos --output-on-failure
build/apple/venv/bin/python -B tools/package_ios.py \
  --app 'build/apple/phase6/ios/Unreal Tournament 3.app' \
  --provisioned-app build/apple/phase6/probe/Release-iphoneos/ut3-ios-probe.app \
  --identity "$UT3_SIGN_IDENTITY" \
  --output 'build/apple/phase6/resolution/device/Unreal Tournament 3.app'
xcrun devicectl device install app --device "$UT3_DEVICE" --timeout 50 \
  'build/apple/phase6/resolution/device/Unreal Tournament 3.app'
xcrun devicectl device process launch --device "$UT3_DEVICE" \
  --terminate-existing --console org.ut3.port.ios.probe \
  > build/apple/phase6/resolution/device-launch.log 2>&1
```

Xcode asset compiler, signing, physical-device access and networking regression tests used authorized host access. Restricted `actool --help` failed to connect to Xcode services; the actual authorized native build successfully compiled the catalog. The duplicate MoltenVK link warning remains. Existing audio setup and guest heap-detach diagnostics remain documented in [IOS_GAMEPLAY.md](IOS_GAMEPLAY.md). No performance benchmark or Phase 7 work was performed. The requested larger-resolution touch, resolution persistence and icon checks are accepted by the owner. Remaining Phase 6 risks are unchanged; Phase 7 requires separate approval.
