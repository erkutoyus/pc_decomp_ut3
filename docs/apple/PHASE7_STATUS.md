# Phase 7 — iPhone performance, 2026-11-18

Phase 7 is authorized. This is a measured 720p/60 FPS milestone, not a claim that startup stutters, thermal behavior or battery optimization are finished. Phase 6 acceptance remains recorded separately.

## Target and preserved behavior

Owner preference: 1280×720 at 60 FPS; 1920×1080 remains selectable and persistent through the original video settings. The iOS launcher supplies a default 60 FPS cap without overriding an explicit developer setting or forcing a resolution on every launch. The owner's INI was backed up and only its `SystemSettings` ResX/ResY fields were changed to 1280/720. Offline profile selection can subsequently apply its own preferences; use the original Apply/Accept flow if needed. No profile binary or key validation was patched.

The Home Screen display name is explicitly **Unreal Tournament 3**. Existing icon assets, bundle identifier, signing identity, saves and native controller/touch/keyboard/audio behavior are retained. Diagnostic and completed timed-test screens stay awake; normal background transitions still release input and pause audio/engine work.

## Findings and accepted optimization

Device: iPhone 17 Pro Max, A19 Pro, iOS 27.0.1, connected to the M4. The build uses Apple Clang 21 / iPhoneOS 27.2 SDK. Original static ARM64 recompilation, guest ABI, MoltenVK 1.4.2 and pinned DXVK Native revision `0cf05780abd7250c2cd713b7749cf32180157cf5` remain in place.

A 50-second Instruments launch capture identified original guest SHA-1 code, filesystem metadata work and LZO decompression during startup. In the selected first five seconds SHA-1 had 702 of 3,731 process samples; these are samples, not exact CPU durations. LZO led the selected 8–15 second window. Decompression and file semantics were not weakened.

`tools/apple_rotates.py` replaces exactly 256 iterative 32-bit rotate loops in the SHA-256-pinned original `sub_00B4F5F0` body with equivalent masked rotates. Every subsequent flag update, guest access, register and return remains intact. The pass rejects an unexpected body. It is enabled by default for fresh iOS builds and remains separately selectable with `UT3_APPLE_SHA1_ROTATES`. Generated originals are preserved.

The physical-phone differential fixture checks 2,000 randomized cases against the complete original function (all registers, flags and 128 KiB memory), plus an independent CommonCrypto compression-state check. With production memory-provenance flags, 100,000 blocks took 0.106137 s originally and 0.037643 s after the pass: **2.82× for this kernel**, not for the whole game. Status 0. The final installed repeat also passed: 0.105675 s versus 0.041579 s, **2.54×**. This variation is why kernel timings are not presented as a guaranteed whole-game speedup. M4 differential and sanitizer runs also passed.

## Real UT3 submission measurements

Measurements below are gaps between **accepted Vulkan Presents**, not GPU completion, displayed FPS or controller latency. `world=DM-Deck` telemetry verifies actual map execution. The harness uses eight-player spectator startup, fixed seed, no score/time limit, 60 FPS cap and isolated input; bot activity can still vary. CSV excludes time before first Present. Native first-Present timing starts at bridge initialization, not the Home Screen tap.

| 720p window | Original rotates | Direct rotates |
| --- | ---: | ---: |
| First accepted Present | 9,213.108 ms | 8,646.235 ms |
| Initial 30 s mean gap | 17.210 ms | 17.156 ms |
| Initial 30 s p99 | 18.874 ms | 18.020 ms |
| Initial 30 s maximum | 210.831 ms | 209.773 ms |
| Initial 30 s gaps >100 ms | 6 | 5 |

This is one pair, with OS/driver cache history and bot variation; the observed 0.567 s earlier first Present is not a statistical performance guarantee. The original run settles near 60 FPS too.

In the optimized five-minute run, the unprofiled 30–230 s window averaged **59.68 submissions/s**, p99 **16.819 ms**. It still contained two gaps above 100 ms and a **700.368 ms** maximum. Three serial graphics pipeline creation calls (364.466 + 179.997 + 164.102 ms) on the same thread coincide with that hitch. Startup hitches also overlap multi-MiB package reads and CPU loading/decompression. These are unresolved, observable costs; a lower pixel count cannot eliminate them.

A 20-second Metal System Trace was captured late in that run. That portion is excluded from the unprofiled comparison. The exported UT3 depth-0 Active intervals cover 14.869 s across a 20.769 s observed span (union across vertex, fragment and compute; overlapping events merged). This is instrumented GPU activity, not per-frame completion time or an energy measurement. USB charging, thermal history and instrument overhead prevent a controlled battery-life claim. Thermal state rose from nominal through fair to serious during the longer session; sustained thermal limits remain work to do.

The final 170-second ordinary-path test (replay disabled, warm learned pipeline caches) captured 161.697 s after first Present. Initial 30 s: mean 17.061 ms, p99 17.652 ms, maximum 240.860 ms, four gaps above 100 ms. From 30 s onward, both reported windows were about 59.99 submissions/s, p99 below 16.77 ms, with no gaps above 25 ms; the larger window maximum was 19.822 ms. Map telemetry remained DM-Deck and thermal state nominal. This is a warm-run observation after other tests, not proof that the earlier 700 ms hitch cannot recur.

Two compiler workers versus the existing six and a 50 µs query-poll wait did not establish a repeatable frame-time improvement. Neither is enabled. Query correctness and original default polling are preserved.

## Shader warm-up experiment

An optional Apple-only cache records successful native D3D9 shader bytecode and can register it through the same public native CreateShader APIs on a subsequent device. Original shader creation/draw calls and HRESULTs remain unchanged. The pinned DXVK device retains common shader modules and its existing state cache can compile known pipeline combinations once those modules register. No pipeline is assumed ready without the original backend's synchronization.

`UT3_SHADER_WARMUP=learn` records without replay; `1` enables replay; absent/0 disables it. The ordinary app currently leaves it disabled. Replay is restricted to HWVP, a maximum of 1,024 registrations and a soft 500 ms budget (one native call can overrun). Cache limits are 16 MiB / 4,096 records, with structural SM2/3 token checks, checksum, atomic replacement, bounded parsing and normal on-demand fallback. Metadata eviction never evicts live DXVK resources. The codec is not a semantic validator for arbitrary shader programs; only bytecode returned by successful native GetFunction is recorded. Internal fixed-function/native shaders are outside this cache.

Both iPhone D3D9 fixture runs (learn and replay) passed exact pixel checks, dynamic samplers, Reset/GetBackBuffer/Present through 1080p with Metal API/GPU validation. Eight shaders replayed successfully in 0.338 ms with zero failures. Real-game replay is **rejected for ordinary play**: registering 1,024 shaders in 145.085 ms triggered a large background pipeline-compile backlog (345 logged calls above 10 ms spanned 56.505 s of completion timestamps; the longest call was 2,269.160 ms), with no accepted first Present before the experiment was stopped. The soft registration budget does not bound downstream pipeline work. The fixture success did not predict game startup performance. Replay remains disabled; do not turn it on based on the fixture alone. Private shader caches contain owner-derived game data and must not be redistributed.

## Files and reproducibility

Primary changes: `tools/apple_rotates.py`, `tools/prepare_macos.py`, `CMakeLists.txt`, iOS CMake/Application/Info.plist; `tests/test_apple_sha1_rotate.c`, `tests/test_apple_rotates.py`; frame/profile instrumentation in `platform/apple/frame.c` and `engine/dxvk/bridge.cpp`; `tools/analyze_apple_frames.py`, `tests/test_apple_frame_analysis.py`; opt-in DXVK timing overlay in `tools/d3d9_profiling.py` / `tools/build_dxvk_ios.py`; optional `engine/dxvk/shader_warmup*` and its codec test. No dependency revision upgrade or Android-reference removal was needed.

Exact machine-local receipts, raw traces, private captures, configurations and logs are under `build/apple/phase7/` (untracked). The iOS CMake cache records dependency paths; preparation and DXVK receipts record source/pass hashes. Build/sign/install are separate steps:

```sh
cmake --build build/apple/phase6/ios --parallel 8
# tools/package_ios.py --help documents --app, --provisioned-app,
# --identity and --output. Reuse the owner's existing profile and app ID.
xcrun devicectl device install app --device "$ut3_device" "$ut3_signed_app"
xcrun devicectl device process launch --device "$ut3_device" \
  --terminate-existing --console org.ut3.port.ios.probe --selftest
xcrun devicectl device process launch --device "$ut3_device" \
  --terminate-existing --console org.ut3.port.ios.probe --validate-sha1
xcrun devicectl device process launch --device "$ut3_device" \
  --terminate-existing --environment-variables \
  '{"MTL_DEBUG_LAYER":"1","MTL_SHADER_VALIDATION":"1"}' \
  --console org.ut3.port.ios.probe --validate-d3d9 --dynamic-samplers
cmake --build build/apple/phase5/macos --parallel 8
ctest --test-dir build/apple/phase5/macos --output-on-failure
python3 -B -m unittest tests.test_apple_rotates tests.test_apple_frame_analysis
python3 tools/analyze_apple_frames.py build/apple/phase7/optimized720-verified.csv \
  --window steady:30:230
```

Use the current device's identifier; signing material and original keys are deliberately absent here. A relative `UT3_FRAME_TRACE=label.csv` resolves inside the current app container's UserData, which avoids stale UUIDs after reinstall. `UT3_PROFILE=1` adds map/thermal/physical-footprint telemetry. Optional pipeline call timing requires a DXVK build made with `tools/build_dxvk_ios.py --profile-pipelines`, then `UT3_PIPELINE_TRACE=1`. Timed runs use `UT3_BENCHMARK_SECONDS=30..600`, pause at completion and disable physical input only for that test. Do not use it for interactive play.

The exact map argument is:

```text
"C:\Games\UT3\Binaries\UT3.exe" DM-Deck?NumPlay=8?SpectatorOnly=1?QuickStart=1?TimeLimit=0?GoalScore=0 -nosplash -nomovie -nosteam -onethread -fixedseed -ResX=1280 -ResY=720
```

Restore identical DXVK state/Vulkan pipeline caches before paired experiments and preserve the best warm caches for ordinary play. Do not infer deterministic full-match results from a spectator benchmark.

## Tests, failures and remaining limits

- Latest M4 native suite: **14/14 PASS** with loopback access. The restricted-sandbox run had 13/14 PASS because `wsa_readiness` could not bind its loopback socket; no source change was needed to pass outside that restriction.
- Python rotate/frame-analysis tests: **6/6 PASS**.
- Codec: AddressSanitizer/UBSan PASS, including every truncation and single-byte corruption, bounds and valid-checksum structural errors. Initial test code mutated an already-zero byte; the fixture was corrected before the successful run.
- Final installed device runtime self-test and production SHA-1 differential fixture: status 0. Final Metal-validated UT3 capture shows the original 1280×720 “Precaching...” loading frame; original engine exit code 0, no reported Metal validation assertion. This capture is not a match screenshot. The normal interactive launcher was restored afterward, and copied saved INI fields confirm 1280×720. D3D9 Metal validation: status 0, including 720p and 1080p resets and exact pixel readback.
- Existing guest detach produces 1,472 invalid-block HeapFree warnings. OpenAL/EAX configuration has three AL_OUT_OF_MEMORY and one AL_INVALID_NAME errors while audible output continues. Neither is hidden or fixed by this performance work.
- Apple actool aborted under the restricted sandbox when unable to reach CoreSimulator services; the same build/sign step succeeded with required access. A final CLI harness attempt passed an empty environment object, which CoreDevice rejected before app launch; the harness was corrected to omit that option when empty. Its capture success matcher also initially expected a returned-worker status; the original game exits through `process exit 0`. The preserved log confirms exit code 0 and the captured frame, and the reporting matcher was corrected.
- Initial PID-attached/time-profiler launch attempts failed or disconnected; later device-wide and Instruments-owned launch captures succeeded. Original logs remain preserved.
- Older iOS versions, long unplugged thermal/battery runs, route changes, memory-pressure handling and end-to-end input/audio latency remain unverified. No 120 FPS, battery-life or all-hitches-fixed claim is made.

Next work should isolate package-load/decompression costs and pipeline compilation using controlled cold/warm comparisons, validate any prewarming against actual resource lifetime and memory pressure, then run sustained unplugged GameSir playtests. Preserve rendering, profile/key validation and real occlusion-query correctness throughout.

## Owner playtest and display-name follow-up

The owner subsequently played a match on the installed performance build: GameSir controller and sound work, with no major issues reported. This is owner feedback, separate from the automated spectator timing captures.

The owner still saw `UnrealTournam..` on the Home Screen. CoreDevice's installed-app inventory reports build 7 and `Unreal Tournament 3`, matching the signed plist; there is no localized InfoPlist.strings override. Thus a missing ASCII-space metadata update does not explain the visible result. Build 8 tries explicit U+00A0 nonbreaking spaces in CFBundleDisplayName, while CFBundleName, executable, bundle identifier and accessible spoken name retain the ordinary title. This is a presentation workaround, not a guarantee that the full 19-character title will fit. Build 8 was signed and installed successfully, and CoreDevice reports the two U+00A0 separators and version 8. All file-backed Mach-O sections and Assets.car match build 7; only metadata/signatures changed. An initial whole-executable byte comparison failed because re-signing changes embedded signature data; section comparison correctly verifies unchanged compiled content. The owner confirmed build 8 still appears as `UnrealTournam..`; the nonbreaking-space workaround did not resolve the visible label. The installed-app inventory contains only one UT3 application. The owner chose to keep the full title “Unreal Tournament 3” rather than a shorter “UT3” Home Screen label. The visible truncation remains accepted for now; no successful label-rendering fix is claimed. No uninstall or owner-data removal was performed. Signature verification passed with keychain trust access; a restricted-sandbox verification reported CSSMERR_TP_NOT_TRUSTED.

Apple documents CFBundleDisplayName as the Home Screen name in [QA1823](https://developer.apple.com/library/archive/qa/qa1823/_index.html). The whitespace workaround is an experiment based on the observed metadata/display mismatch, not documented Apple behavior.
