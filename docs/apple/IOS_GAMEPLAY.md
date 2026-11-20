# Phase 6 iPhone gameplay and lifecycle — 2026-11-18

Current checkpoint: Phase 6 owner acceptance is recorded in [IOS_GAMEPLAY.md](IOS_GAMEPLAY.md); Phase 7 is authorized and its performance results are in [PHASE7_STATUS.md](PHASE7_STATUS.md). Earlier pending/not-started statements below describe historical checkpoints.

Phase 6 only. Performance work remains deferred; Phase 7 has not started.

## Actual results

- Owner verified native keyboard typing, deletion and Done in the UT3 User Name field, and audible clear menu audio.
- Owner completed an offline match on the iPhone 17 Pro Max using GameSir X5 Lite. Native logs identify `GameSir-X5 Lite_S` and physical controller events. This is human gameplay verification, not an instrumented full-match recording. Owner described heavy initial stutters followed by roughly 60 FPS with occasional hitches; this is not a measured sustained benchmark.
- The installed touch/resume build starts the game, accepts Vulkan Present and emits nonzero RemoteIO samples at 48 kHz stereo, with no nonfinite samples observed. The owner subsequently confirmed correct touch selection, keyboard operation, one-second button disappearance, and working sound/controller after restoring the app during the requested repeated minimize/restore check.
- The updated app received four keyboard show/hide cycles and physical GameSir events, then exited through guest ExitProcess(0), process code 0. This attached run has no background/foreground cycle; the subsequent audio/controller recovery result comes from the owner’s physical test, not this log. Its DLL-detach sequence repeats the known 1,472 HeapFree warnings.
- macOS host regression: **12/12 PASS**, 8.26 s. New fixtures cover the real text-input queue, touch-coordinate mapping and suspended-frame wakeup. Pointer mapping also passed AddressSanitizer/UndefinedBehaviorSanitizer. These fixtures do not replace UIKit/device testing.

Evidence below `build/apple/phase6/gameplay/`: `menu-device.log` (previous keyboard/audio/controller build), `touch-resume-device.log`, `touch-resume-{package,install}.log`, `touch-resume-ready-build.log`, `macos-final-tests.log`, and the copied `full-match-userdata/`. The copied UE3 Launch.log records front-end startup; it does not independently prove the reported full match. No match map name is asserted from it.

## Files changed

Build and tests: root `CMakeLists.txt`, `tools/build_openal_macos.py`, `.gitignore`, and `tests/test_{apple_text,apple_frame_gate,ios_pointer}.c`. Shared runtime: `engine/host/input.{c,h}`, `engine/host/openal.c`, `platform/apple/frame.c`. UIKit: `platform/apple/ios/{Application.m,GameView.m,GameView.h,CMakeLists.txt}` and `platform/apple/Pointer.h`. Status, architecture, dependency, build and test documentation link this report. Existing game, graphics compatibility and CD-key work is retained.

## Shared engine and native ownership

`engine/host/input.c` accepts bounded validated UTF-16 into the existing WM_CHAR queue, retaining surrogate pairs. The guest owns text, deletion and selection. UIKeyInput in `platform/apple/ios/GameView.m` supplies the native keyboard, Backspace and Done. No typed text is logged. GameController extended gamepad events feed the existing XInput snapshot/edge logic on the main queue. Focus loss, controller disconnect and shell shutdown release input. Menu+Y can toggle the keyboard.

Single-touch input forwards absolute guest coordinates, relative motion and left-button down/up through the existing mouse bridge. `platform/apple/Pointer.h` matches the native Present aspect-ratio rectangle, converting UIKit points to drawable pixels and then guest pixels without a Y flip. Initial touches outside the image do not click the guest; captured drags clamp to its edges. Cancellation, keyboard opening and focus loss release the mouse button. This supplies UI mouse interaction, without adding gameplay touch controls.

The Keyboard UIButton starts hidden. A game-view touch reveals it and restarts a one-second timer in common run-loop modes. Pressing the button holds the timer; activation opens the keyboard and hides the button. Focus loss/disconnect invalidates the timer. Callback references are weak; native input observers and controller handlers are removed when stopped.

OpenAL reuses the pinned CoreAudio backend's existing iOS RemoteIO branch, the guest OpenAL ABI, source/buffer/context ownership, EAX support and callback meter. `platform/apple/ios/Application.m` owns AVAudioSession. Inactive scenes release input and pause audio and the engine at its next frame boundary; backgrounding deactivates the session. Foregrounding always reactivates the session and reopens/resumes the retained playback device before releasing the engine gate. A stale interruption flag previously prevented recovery if iOS did not deliver an end notification across suspension. Notifications are now serialized on the main queue and a successful foreground activation clears that flag. This is the diagnosed recovery-path defect; the owner has now confirmed audible sound recovery and retained controller input after restoring the app.

`platform/apple/frame.c` gates frames only for UT3_IOS. Shutdown wakes a suspended engine to consume its close request. Existing HUD/camera/audio frame observers remain. This does not assert that every possible long-running loading operation has already quiesced at the instant iOS backgrounds the app.

## Reproducible build and deployment

The preceding iOS toolchain, MoltenVK and DXVK cache configuration is in [BUILD_PLAN.md](BUILD_PLAN.md). Add native audio:

```sh
build/apple/venv/bin/python -uB tools/build_openal_macos.py --ios \
  --archive build/apple/phase4-inputs/openal-soft.tar.gz \
  --build build/apple/phase6/openal-ios
cmake -S . -B build/apple/phase6/ios -G Ninja \
  -DUT3_IOS_OPENAL="$PWD/build/apple/phase6/openal-ios/libopenal.1.25.2.dylib" \
  -DUT3_IOS_OPENAL_INCLUDE="$PWD/build/apple/phase6/openal-ios-source-b2c48f7718ef/include"
cmake --build build/apple/phase6/ios --parallel 8
cmake --build build/apple/phase5/macos --parallel 8
ctest --test-dir build/apple/phase5/macos --output-on-failure
build/apple/venv/bin/python -B tools/package_ios.py \
  --app 'build/apple/phase6/ios/Unreal Tournament 3.app' \
  --provisioned-app build/apple/phase6/probe/Release-iphoneos/ut3-ios-probe.app \
  --identity "$UT3_SIGN_IDENTITY" \
  --output 'build/apple/phase6/gameplay/touch-resume-device/Unreal Tournament 3.app'
xcrun devicectl device install app --device "$UT3_DEVICE" --timeout 50 \
  'build/apple/phase6/gameplay/touch-resume-device/Unreal Tournament 3.app'
xcrun devicectl device process launch --device "$UT3_DEVICE" \
  --terminate-existing --console org.ut3.port.ios.probe \
  > build/apple/phase6/gameplay/touch-resume-device.log 2>&1
```

Signing/device operations used authorized host access. The existing application identifier and Documents were preserved. Owner game assets and `cdkey.txt` are not embedded or redistributed. Original key validation is unchanged. A normal launch enables audio; explicit `UT3_COMMAND_LINE` now overrides the default front-end command for targeted diagnostics. Older diagnostic `-nosound` examples should not be used for audio acceptance.

OpenAL Soft remains revision `b2c48f7718ef3fcf67921a8b6534c4914e328970`, archive SHA-256 `6a3e5f80058ecf994a6885d7db5013629a259c659ab40a6f17db8963ceb211b2`. Unsigned iOS dylib SHA-256 `71e41581c577657851099c3de4ad6724c0505586a2ab2eb86c7cc9c412c04319`; receipt `build/apple/phase6/openal-ios/receipt.json`. No dependency upgrade or Android runtime dependency was added. Shared portable sources and Android reference remain preserved.

## Failures, risks and next verification

- Latest launch with the retained OpenAL/EAX configuration reports three `AL_OUT_OF_MEMORY` and one `AL_INVALID_NAME` errors during game audio setup. Output continues with nonzero samples; these errors are unresolved and are not hidden or treated as a clean audio regression. The previous Generic Software configuration had no observed game errors. Do not disable EAX to mask this finding.
- Existing 1,472 guest HeapFree warnings on DLL detach remain unresolved, as documented in [PHASE6_STATUS.md](PHASE6_STATUS.md).
- First text fixture link lacked weak no-publisher stubs on Mach-O; corrected. Final native build warns about duplicate MoltenVK linkage, then links successfully. No tests were disabled.
- iPhone Mirroring automation failed with an expired tool continuation. Device logs and owner feedback are the verification sources; no automated screen interaction is claimed.
- Owner acceptance on 2026-11-18: touch selects correctly; keyboard works; its button disappears after one second; sound and GameSir input still work after restoring. This closes the reported touch/button/foreground-audio defects for the tested scenario. Route changes, external audio interruptions and memory pressure remain separate unverified cases. Successful PCM callbacks alone were not used to infer audible recovery.
- Initial shader/loading hitches, sustained thermal/battery behavior and optimization remain unmeasured or deferred. Do not start Phase 7 without owner approval.
