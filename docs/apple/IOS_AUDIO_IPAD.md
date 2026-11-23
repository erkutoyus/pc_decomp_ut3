# Build 12 — external music and native iPad windows

2026-11-23. The owner confirmed build 11 works and the UT3 app/container names are correct. This update addresses Spotify being interrupted and the M2 iPad screenshots showing iPhone compatibility mode.

## Changes and reasons

`platform/apple/ios/Application.m` configures Playback with `AVAudioSessionCategoryOptionMixWithOthers`. Playback without options interrupted Spotify when UT3 activated its session. There is no ducking option or background-audio entitlement. Existing game-audio suspension, session deactivation, interruptions and foreground recovery are retained. OpenAL's CoreAudio backend does not configure a competing AVAudioSession category. See [Apple's playback category documentation](https://developer.apple.com/documentation/AVFAudio/AVAudioSession/Category-swift.struct/playback).

`platform/apple/ios/Info.plist.in` explicitly supplies `UIDeviceFamily=[1,2]`. The existing Xcode TARGETED_DEVICE_FAMILY property does not populate the plist when building with Ninja. Omitting the key defaults to iPhone support, matching the owner's small compatibility window and resize button. The same ARM64 binary and IPA now declare native iPhone/iPad support. Development packaging retains this declaration instead of replacing it with scaffold metadata. Unsigned IPA packaging rejects absent or single-device family metadata, with a regression covering those cases.

The root view controller hides the system status bar. iPhone retains landscape orientations; iPad advertises all four orientations for resizable native scenes. The existing CAMetalLayer layout updates drawable dimensions and guest touch mapping already accounts for the aspect-fit destination. No extra compatibility/fullscreen opt-out flag is added: [Apple deprecates UIRequiresFullScreen](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key). The OS may still show a window if the owner selects windowed multitasking; this change removes iPhone compatibility mode rather than overriding that choice.

Selected game resolution remains independent of native window size. A 16:9 or 5:4 guest image may have bars on an iPad screen. It is not stretched, cropped or automatically raised to native screen resolution. Touch regression now covers a 4:3 iPad view with the owner's 1280×1024 guest resolution, edge reachability and rotation with a retained 720p backbuffer.

Display name UT3, pre-SideStore bundle identifier org.ut3.port.ios and flat shared-file layout are unchanged. Build number is 12. No dependency revisions or generated game code changed.

## Actual validation

Commands run on the M4:

```sh
cmake --build build/apple/ios --parallel 8
cmake --build build/apple/macos --target ut3-test-ios-pointer --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
build/apple/venv/bin/python -B -m unittest tests.test_package_ipa -v
```

- iOS native compile/link and Apple icon generation: exit 0.
- M4 CTest: 16/16 PASS, including the extended iPad pointer cases.
- Python IPA regressions: 5/5 PASS.
- Staged current dependency notices via `build_apple.stage_notices`, then packaged using `package_ipa.package` into `dist/ios/Unreal Tournament 3.ipa`. Physical-device ARM64 target, exact build 12, UT3 display name, stable source identifier, device families [1,2], four iPad orientations, Payload identity/CRC and exclusion of game/key/save/provisioning data verified.
- `git diff --check`: PASS.

Local transcripts: `build/apple/cleanup/build12-{ios,pointer-build,native-tests,package-tests,package}.log`.

## Device verification still required

Only the iPhone 17 Pro Max was connected during this update; the M2 iPad was not available. The new unsigned IPA must be re-signed/updated through SideStore before runtime checks. No build-12 Spotify coexistence or physical iPad fullscreen result is claimed here.

Update the existing app without uninstalling on each device. Start Spotify before UT3; verify music continues alongside menu/game audio, then background/restore UT3 two or three times and check both audio streams and controller input. On the iPad verify the compatibility resize button is gone, the native view uses the full available window, rotation/window resizing preserve aspect ratio and touch reaches menu edges. Check Keyboard and controller input during a short offline match. Keep personal game data in the existing flat UT3 container.
