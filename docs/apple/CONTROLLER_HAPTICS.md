# Controller vibration — build 13

2026-11-23. Scope: diagnose the original UT3 PC vibration failure, preserve original waveforms/profile preference, and route the resulting XInput commands to iOS controller haptics. No simulated shot/damage rumble replaces the game logic.

## Finding and controlled gameplay evidence

An isolated M4 DM-Morbias match used the original game, native renderer and a diagnostic XInput controller whose trigger alternates every second (`UT3_TEST_RUMBLE_PAD=1`). This injects controller input only; it does not generate vibration. Normal launches never enable it.

Baseline: the local UTPlayerController's `ForceFeedbackManager` was absent, its configured `ForceFeedbackManagerClassName` was empty, and the original Xna update did not run. The game reached an offline match; no nonzero XInput motor marker appeared. Exposing the vibration checkbox alone does not initialize this missing backend.

Controlled configuration: selecting `WinDrv.XnaForceFeedbackManager` created the original manager with virtual update address `0x00A12890`. The original game emitted `XInputSetState` motor values **37713 / 31427**. A first exploratory config insertion failed because a later empty derived-controller entry overrode it; inspection of the actual class configuration identified that mistake. Setting the derived-controller entry resolved it.

Automatic fix: rerunning the formerly failing profile without hand edits created the manager and emitted **37707 / 31423**. The synthetic trigger fixture ran in a real offline map with accepted native Vulkan Presents, not a direct call to the motor setter. These measurements establish original game-generated rumble on the M4 shared runtime. They do not establish physical iPad output or attribute each waveform to a particular firing/damage event.

Read-only binary inspection confirms that `0x00A12890` calculates motor strengths through `0x00A127A0`, then calls thunk `0x0146FECC` / IAT `0x01729AC0`, which imports XINPUT1_3 ordinal 3 (XInputSetState). The original stop function is `0x00A12670`. The original PC menu's ControllerVibration provider has `bRemoveOnPC=1`.

## Implementation

- `platform/apple/ControllerConfig.m`: fills missing/empty native backend class entries for Engine.PlayerController and UTGame.UTPlayerController. Nonempty custom classes remain; inherited Engine custom classes are preserved. The generated vibration menu option is exposed. Profile vibration on/off values and waveform code are untouched.
- Original game config stays read-only. A derived `UserData/AppleConfig/UTGame/Config/DefaultGame.ini` overlay supplies first-launch defaults through the existing file overlay mechanism. An existing user `Documents/My Games/Unreal Tournament 3/UTGame/Config/UTGame.ini` is patched atomically with a one-time `.before-controller-haptics` backup. Text encoding and line endings are retained. Unchanged overlay content keeps its mtime, avoiding unnecessary UE3 config regeneration on relaunch.
- `engine/host/input.c`: exports the locked motor mailbox to Apple; commands expire after 250 ms. Zero, disconnect and focus-loss clearing prevent old rumble replay. iOS consumes the same left/right 16-bit strengths. The first nonzero game command is logged.
- `engine/host/features.c`: bounded diagnostics report manager presence, original update calls, waveform presence, pause flag and scale every 15 seconds. The wrapper delegates to the original manager; no waveform math or game-generated motor intensity is replaced.
- `platform/apple/ControllerHaptics.{h,m}`: Game Controller/Core Haptics engines target the selected controller. Separate handle localities receive separate motor strengths; controllers exposing a combined locality use the greater strength. Unsupported controllers are logged and remain usable for input, with no phone-vibration fallback.
- Each hardware event lasts at most 200 ms. Active nonzero commands renew it at 150 ms; changing strengths use dynamic intensity parameters between renewals. No infinite vibration loop survives a stalled run loop. Zero commands stop promptly; controller change, suspension and teardown stop/release engines and timers. Server stops/resets invalidate players for re-creation. The timer holds the view weakly and runs only for a supported active controller. Controller engines play haptics only; the existing Spotify-mixing session is retained.
- Build 13 remains one universal iPhone/iPad IPA with the same SideStore source identity, UT3 display name and flat file layout. CoreHaptics and Foundation are system frameworks; no third-party dependency revisions changed.

Apple API references: [controller haptics](https://developer.apple.com/documentation/gamecontroller/gccontroller/haptics), [controller engines and localities](https://developer.apple.com/documentation/gamecontroller/gcdevicehaptics/createengine%28withlocality%3A%29), [dynamic continuous intensity](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time).

## Commands and validation

```sh
cmake --build build/apple/macos --parallel 8
cmake --build build/apple/ios --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
build/apple/venv/bin/python -B -m unittest tests.test_package_ipa -v
build/apple/macos/ut3-runtime-selftest --game /Volumes/NVME512/Github/UT3 --data build/apple/cleanup/rumble-selftest --selftest
```

Gameplay launches used LaunchServices with `--game` and an isolated `--data`, `UT3_TEST_RUMBLE_PAD=1`, and:

```text
UT3_COMMAND_LINE="C:\Games\UT3\Binaries\UT3.exe" DM-Morbias?NumPlay=4?QuickStart=1?TimeLimit=0?GoalScore=0 -nosplash -nomovie -nosteam -onethread -fixedseed -ResX=1280 -ResY=720
```

The native app was quit through AppKit between runs. Machine-local logs remain under `build/apple/cleanup/rumble-*-console.log`, the isolated `rumble-game-*` data folders, and `build13-*` build/test/package logs. Packaging uses `build_apple.stage_notices` and `package_ipa.package`, as the standard build script does, producing `dist/ios/Unreal Tournament 3.ipa`.

Verification: native M4 compile and physical-device ARM64 iOS compile/link succeeded; native CTest **17/17 PASS**, IPA tests **5/5 PASS**. Original headless self-test: PE binding, DLL/TLS startup, guest heap and static dispatch PASS, process exit 0. The automatic-fix offline match reached START MATCH and exited through AppKit with guest status 0 and no worker outstanding. New real-filesystem config regression covers original-input preservation, first-run overlay, scoped menu visibility, UTF16 user config, backup, custom backend inheritance, unchanged mtime and idempotent relaunch. The real input fixture also covers channel packing, ignored nonzero slot, exact 250 ms expiry, explicit stop and disconnect/reconnect clearing. IPA identity/Payload/CRC and asset/key/save/provisioning exclusion pass.

Development failures were fixed: isolated input fixture initially lacked new diagnostic symbols; Objective-C enumeration variables required ARC ownership for reassignment; the first haptics constructor needed a return and handler cleanup corrections. Final iOS link retains the pre-existing duplicate MoltenVK library warning. LaunchServices rejected console redirection to the external volume (-10810); `/tmp` redirection succeeded. Offline gameplay also emits existing missing VoiceInterface script warnings; this change does not resolve voice networking.

## iPad owner test still required

Update build 13 through the same SideStore entry without uninstalling. Connect the PlayStation controller before launch, keep Controller Vibration enabled, and load an offline match. Check firing and taking damage, toggle vibration off/on, background/restore, then disconnect/reconnect the controller. Verify vibration stops when expected and input/audio/Spotify still work. Physical controller support, strength/latency and sustained performance have not been measured here. If it stays silent, `UserData/ut3.log` distinguishes original game output (`[input] first gamepad rumble`) from iOS capability/output (`[ios-haptics]`). No key or typed credentials are included in these diagnostics.

## Owner confirmation and shared macOS follow-up

The owner subsequently confirmed build 13 vibration works on the iPad with a DualShock 4. During investigation the connected iPad initially still reported build 12; the distinctly named UT3-build13.ipa avoided selecting the older IPA. No haptics-code change was needed for that confirmation. The same implementation now lives in platform/apple and is compiled by AppKit and UIKit. Updated shared logs use `[apple-haptics]`; the confirmed iOS build 13 used `[ios-haptics]`. The owner then confirmed physical macOS vibration on build 14 with the Wireless Controller/DualShock 4. The installed app logged original game motor values 37712/31426 followed by successful separate-handle submission. The isolated firing fixture shut down cleanly and the normal app was restored.

## Isolated channel check — 2026-11-23

After the owner suspected heavy/light reversal, the full XInput-to-Apple mapping was inspected: XInput left/low-frequency is stored in the high word of the host mailbox and passed to the Left Handle engine; right/high-frequency is stored in the low word and passed to Right Handle. The original UT3 waveform code and XInput shim preserve that ordering. A disposable AppKit fixture compiled the exact shared ControllerHaptics.m and let the owner request A=0x99990000 and B=0x00009999, each for 0.7 seconds at equal strength. The owner confirmed A=heavy left rumble and B=light right buzz, the expected result. The Mac routing is physically verified; no global swap, waveform edit or haptic-strength adjustment was made. The fixture was stopped after use and is not packaged with the game. iOS uses the same routing; this isolated test did not run on the iPad.

References: [Microsoft XInput motor frequencies](https://learn.microsoft.com/en-us/windows/win32/xinput/getting-started-with-xinput), [Apple controller-engine localities](https://developer.apple.com/documentation/gamecontroller/gcdevicehaptics/createengine%28withlocality%3A%29).
