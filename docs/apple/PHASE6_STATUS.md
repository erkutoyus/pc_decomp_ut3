# Phase 6 device bring-up — 2026-11-17

**Phase 6 gameplay and requested foreground-recovery checks accepted by the owner. Remaining robustness risks are recorded below. Phase 7 is now authorized; see [PHASE7_STATUS.md](PHASE7_STATUS.md) for the subsequent performance work.**

2026-11-18 update: the owner verified keyboard typing/deletion/Done, clear audio and a complete offline match with the GameSir X5 Lite. The owner also confirmed correct touch-to-mouse selection, keyboard operation, one-second button disappearance, and sound/controller recovery after restoring the app. See [IOS_GAMEPLAY.md](IOS_GAMEPLAY.md) for current results; the initial bring-up account below is historical.

Continuation: the D3D9 device now creates successfully using explicit D3D9 constant bounds and typed read-only unbound descriptors, with truthful Vulkan feature flags. Exact ARGB GPU tests pass with Metal API/shader validation, including dynamic sampler selection. The first actual UT3 frame was captured and presented on the phone (CD-key screen). Real-game Metal validation then exposed heap aliasing during upload; the dedicated-image allocation fix now passes two separate real-game frame-capture/exit runs with Metal API and GPU shader validation enabled. Both exit with code 0; pre-existing guest DLL-detach heap-free warnings remain. See [D3D9_PORTABILITY.md](D3D9_PORTABILITY.md) for source changes, preserved failures, tests and commands.

## Verified hardware and toolchain

Physical iPhone 17 Pro Max (iPhone18,2), A19 Pro, iOS 27.0.1 (24A446). The development machine is the M4 Mac, Apple Clang 21.0.0 and iPhoneOS27.2 SDK. The build minimum is iOS 18.0; that older OS has not been tested. All generated game code is native ARM64 Mach-O. This is static recompilation, with no JIT, Wine, Rosetta or executable guest data. Development signing uses the owner's existing team and one application identifier, `org.ut3.port.ios.probe`. No profile, certificate or private key is published.

## Implemented

- Separate UIKit/WindowScene diagnostic shell, sandbox paths `Documents/Game` and `Documents/UserData`, retaining the common host, generated code and original startup/self-test.
- Public iOS `vm_allocate`/`vm_deallocate` instead of unavailable `mach_vm_*`, retaining macOS implementation. The 4 GiB guest window uses `0x7000000000`, verified on device. The guest ABI remains 32-bit; only the host base differs. Host pages are 16 KiB, guest pages remain 4 KiB.
- iOS ARM64 DXVK cross-build using the existing pinned source/overlays, unchanged required Vulkan features. Embedded signed dylib loads on device. The app links the actual iOS MoltenVK static slice and injects its Vulkan entry point through the existing DXVK loader callback. No macOS driver binary is copied into iOS.
- Existing Metal WSI and D3D9 COM fixture reused. Independent Vulkan fixture is callable from UIKit with the original AppKit CLI fixture preserved.
- iOS networking compilation uses public kqueue EOF reporting where the SDK omits `tcp_fsm.h`. macOS keeps its existing TCP state logic. Real iOS network behavior is not yet regression-tested.
- Reproducible small VM/provisioning fixture in `platform/apple/ios/probe`, and separate signing/package tool. Android reference preserved.

## Actual results

| Test | Result | Local evidence below `build/apple/phase6/` |
| --- | --- | --- |
| Signed VM probe | PASS: 4 GiB at 0x7000000000, protect/commit/read; 16 KiB pages | `probe-scene-device.log` |
| Lower candidate bases | FAIL: 0x400000000 and 0x200000000 return no space | same |
| Existing UT3 runtime self-test | PASS, status 0: PE binding, DLL/TLS startup, heap, static entry lookup. Game entry is intentionally not called. | `runtime-device.log`, `runtime-userdata/` |
| Final app with embedded DXVK, repeated self-test | PASS: all three separate launches returned status 0 (initial runtime, then two runs with embedded DXVK) | `runtime-device-repeat2.log`, `runtime-device-repeat3.log` |
| MoltenVK surface/swapchain/clear/readback/present | PASS, 2868x1320, RGB 37 160 123, every pixel checked | `vulkan-device.log` |
| D3D9 COM fixture | Initial FAIL 8876086a; now PASS with fallback and exact ARGB readback, Metal API/GPU validation enabled | `d3d9-device.log`, `portability-alpha-validation-device.log`, `portability-alpha-dynamic-validation-device.log` |
| macOS regression following shared changes | PASS: 7/7 initially and 7/7 after final shared changes with loopback access | `macos-regression-tests.log`, `macos-regression-final-device-access-tests.log` |
| UT3 first frame | PASS in ordinary run, CD-key screen, 640x480 back buffer; real-game validation subsequently found an upload aliasing bug | `ut3-game-device.log`, `ut3-first-frame-iphone.png`, `metal-alias-crash.ips` |
| Dedicated-image correction, real game with Metal validation | PASS: two launches, capture at 17.992 s and 7.245 s, accepted Present and engine-thread exit, process code 0; no reported Metal API/GPU validation failure | `dedicated-final-ut3-validation-device.log`, `dedicated-repeat-ut3-validation-device.log` |
| Interactive menu/map/offline match | Owner verified a complete offline match with GameSir X5 Lite; native keyboard and sound verified separately | `gameplay/menu-device.log`; owner feedback, not an automated match capture |
| Touch/controller/audio/suspend/resume and sustained memory behavior | Owner verified keyboard, GameSir, audio, touch/timer and sound/controller recovery after restoring; route-change and memory-pressure testing pending | [IOS_GAMEPLAY.md](IOS_GAMEPLAY.md) |

Device runtime output:

```text
[selftest] PE binding, DLL/TLS startup, guest heap and static entry lookup PASS; game entry not executed
[ut3] startup worker finished with status 0
[ut3-ios] runtime self-test finished with status 0
```

## Initial graphics blocker (D3D9 fallback now implemented)

MoltenVK 1.4.2 on this A19 Pro advertises the robustness2 extensions, but reports `robustBufferAccess2=0`, `robustImageAccess2=1`, `nullDescriptor=0`. BC compression and precise occlusion-query feature bits were reported supported; this does not validate all D3D9 formats or game queries. The independent clear fixture succeeds because it does not need the missing features.

The pinned DXVK Native 2.4.1 requires robust buffer access alignment and null descriptors (`src/dxvk/dxvk_adapter.cpp`, device creation lines 394–399). Actual D3D9 creation reaches MoltenVK and reports:

```text
VK_ERROR_FEATURE_NOT_PRESENT: vkCreateDevice(): Requested physical device feature specified by the 1st flag in VkPhysicalDeviceRobustness2FeaturesKHR is not available on this device.
VK_ERROR_FEATURE_NOT_PRESENT: vkCreateDevice(): Requested physical device feature specified by the 3rd flag in VkPhysicalDeviceRobustness2FeaturesKHR is not available on this device.
err:   DxvkAdapter: Failed to create device
[d3d9-probe] COM(parent, 16, 0, 1, 0, 0x40, args, args + 64) failed: 8876086a
[ut3-ios] D3D9 probe finished with status 1
```

No feature requirements were disabled or falsely advertised. No backend upgrade, unrelated renderer, or direct D3D9-to-Metal rewrite was introduced. KosmicKrisp has not been verified or deployed on iOS.

The continuation implements a D3D9-specific fallback, rather than claiming generic Vulkan robustness2. The actual GPU tests now pass. A subsequent real-game validation run found a buffer-to-texture Metal heap-aliasing violation. The scoped dedicated-image correction now passes two real-game first-frame runs with both Metal validations enabled and exit code 0. Continue remaining Phase 6 controls, protected data, audio sessions, gameplay, heap-detach diagnostics and lifecycle work. [Implementation and actual results](D3D9_PORTABILITY.md).

## Failures and limitations preserved

- The first real-game Metal validation run aborted on an aliasing upload. The dedicated-image fix resolves that assertion in the two tested first-frame runs; the original crash and failed log are retained.
- Both validated iOS exits report 1,472 guest `HeapFree(...): not a block of this heap` warnings during DLL detach. The same warning class occurs in Phase 5 macOS repeat/offline logs. Exit code 0 is not a claim of fully correct heap teardown. This remains a shared-runtime lifecycle risk to investigate in Phase 6.
- The final allocation-fix retest was initially denied because the phone was locked. After the owner unlocked it, installation and both actual game validation runs completed.

- Initial installation failed at the free-profile three-app limit. The owner removed an app; installation then succeeded. No other app was removed by the agent.
- Initial VM app used the legacy lifecycle and crashed with SIGTRAP: UIKit requires scene adoption on this device. Fixed with UIWindowScene; successful probe and runtime logs supersede that run. Crash evidence: `probe-crash.ips`.
- First runtime link lacked Foundation/CoreGraphics; corrected linkage. First D3D9 compile lacked the iOS TCP state header; public kqueue EOF path added. Original failed build logs retained.
- Final macOS CTest in the restricted sandbox failed the WinSock readiness fixture at loopback bind (6/7 passed). The same binaries with authorized local socket access passed 7/7 in 0.84 seconds; both logs are retained (`macos-regression-final-tests.log` and `macos-regression-final-device-access-tests.log`).
- Reading development signing metadata under the restricted process returned invalid/empty data; packaging worked with authorized keychain/signing access. Device operations also require device-access permissions.
- Development console sessions report a transport termination when an installed app is replaced or terminated for the next test. Judge test completion by explicit fixture results, not the console process exit status.
- The initial self-test needed only owner-provided `Binaries`. The continuation also copied `Engine` and the approximately 9 GB `UTGame` into the app sandbox for the actual game launch. No proprietary data is packaged with source.
- This is a development diagnostic app, not a finished iOS game or distribution-ready package. Battery facts remain explicitly unknown. No game controls, audio session, suspension protocol or full memory-pressure policy is claimed.
- The captured frame is UT3’s CD-key screen, not an offline match. The ordinary prompt run reported approximately 60 accepted presents/s at a 640x480 game back buffer with a 2868x1320 surface; this is not a sustained gameplay performance result or Phase 7 optimization.

## Files and commands

Build/reproduction commands: [BUILD_PLAN.md](BUILD_PLAN.md), section “Phase 6 iOS device diagnostics”. Main new files: `platform/apple/ios/{CMakeLists.txt,Info.plist.in,Application.m}`, `platform/apple/ios/probe/*`, `tools/{build_dxvk_ios.py,package_ios.py,d3d9_portability.py}`, and `platform/apple/ios/d3d9_{unbound,portability_probe}.inc`. Shared changes: root CMake, host memory/network, DXVK bridge and Vulkan fixture library guard. Documentation and allowlist updated. Existing Android implementation and all prior phase work retained.


## File-based CD key support (2026-11-18)

Completed on macOS and the physical iPhone: the owner-provided `cdkey.txt` passes the original game validator and reaches Login. A synthetic invalid key is rejected. The Mac file-mode backend prevents legacy Keychain authentication UI while retaining records and restoring the previous interaction setting. Native input/audio/gameplay remain Phase 6 work; Phase 7 is not started. File locations, preserved ABI/validation, exact tests, remaining limitations and evidence are in [CDKEY_FILE.md](CDKEY_FILE.md).


## iOS resolution and icon continuation (2026-11-18)

The ordinary launcher no longer forces 640x480 over the saved UE3 resolution. The updated phone launch uses its existing 1280x720 setting; successful iOS back-buffer changes update the full-surface cursor clip. The supplied icon now compiles into the signed iOS bundle. All 12 native host tests pass. The owner verified touch coverage at 1920x1080, a visible Home Screen icon and, after rechecking an initial contrary report, saved resolution persistence. No additional runtime change was required. [Diagnosis, exact commands, changed files and device evidence](IOS_RESOLUTION.md). Phase 7 has not started.
