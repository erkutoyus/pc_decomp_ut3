# Apple migration plan

Current checkpoint: Phase 6 owner acceptance is recorded in [IOS_GAMEPLAY.md](IOS_GAMEPLAY.md); Phase 7 is authorized and its performance results are in [PHASE7_STATUS.md](PHASE7_STATUS.md). Earlier pending/not-started statements below describe historical checkpoints.

This plan uses the current Android release as a behavioral baseline. Start an Apple branch after Phase 0 approval, keep Android builds available, and reuse sources in place while the platform seams settle. Stop for review and approval at each phase boundary.

| Phase | Scope | Evidence required for approval |
| --- | --- | --- |
| 0 | Audit the repository, game inputs, toolchain, VM and dependencies. | Seven documents, known failures recorded, and a bounded Phase 1 design. |
| 1 | Native macOS ARM64 command-line host. | A real `ut3_game_main(game, data, 1)` run on the M4 with an ARM64 Mach-O, exit 0, captured module/TLS/startup output and built-in PASS line. Supplement with VM, calling convention, exception, TLS and thread fixtures. |
| 2 | AppKit application and platform interfaces. | Native window and lifecycle, focus and event routing, keyboard/mouse/controller tests, diagnostics, user-data path, and repeatable orderly shutdown. |
| 3 | Apple WSI and pinned DXVK on ARM64. | Run the isolated Vulkan clear test, D3D9 device and guest COM lifecycle tests, resource/shader tests and the first UT3-rendered frame. Journal each candidate and each stage. |
| 4 | Playable macOS. | Startup, rendered and interactive menu, map load, movement, physical audio, offline match and repeated cold/warm startup and shutdown. Capture CPU/GPU and frame-time baselines. |
| 5 | Remove Android dependencies from the Apple build. | Update each row of the [manifest](REMOVAL_MANIFEST.md), inspect build/link/package closure and rerun gameplay, graphics, audio and teardown tests. Keep the upstream Android reference. |
| 6 | Native device iOS app with shared engine. | Signed installation and runtime self-test on the iPhone 17 Pro Max, Metal-backed Vulkan presentation, first frame, menu, map and offline match, touch/controller/audio, suspend/resume and sandbox checks. |
| 7 | Device profiling and usability. | Sustained matched-session captures under controlled settings, with CPU/GPU timings, shader stalls, memory, thermals, power, audio and input latency and usability notes. Set frame-rate/resolution targets from measured results. |

## First implementation steps after approval

1. Acquire the two hash-pinned VC80 inputs from an authorized source and provision the pinned Python environment. Add explicit arguments for local Steam and VC80 roots without rewriting the tracking manifests. Run the existing verifier and lifter, retaining all configured modules, reports, prepared images and dispatch. If local lifting is blocked, use an authorized Windows producer for the exact same artifacts and record hashes before Apple compilation.
2. Add a small Apple-only CMake/Ninja target and one source manifest. Compile generated C with Apple Clang and preserve behavior-sensitive flags. First prove ARM64 Mach-O symbol naming, linked CRT byte identity, and replacement/original dispatch across call forms. Reuse the existing generators for x87, call masks and same-unit hooks. Track any Apple-specific alias optimization adaptation and test it against the exact mode before promoting it.
3. Implement the minimal Darwin block for reservation, discard, diagnostics, timing and thread platform calls. Use the existing 4 GiB VM and test reserve collision, commit/recommit, release, mapped views, 16 KiB host/4 KiB guest neighbors and signal reporting. If the candidate base fails under signed production layout or randomized runs, isolate the host-base representation change before proceeding.
4. Compile required Win32 export and guest-init code. List the import table, feature-init and startup dependencies explicitly before pruning the source set. Retain the original main, PE binding and DLL/TLS path. Isolate graphics/audio device I/O behind a headless target boundary. If an intentionally unavailable device path is called, fail with the import or operation named and investigate the dependency. Keep shared import registrations and existing feature work. Do not claim a synthetic-dispatch fixture as the game self-test.
5. Run the full existing self-test with the verified Steam directory and a fresh writable data directory. A successful run exercises lifted DLL startup and entry lookup. It leaves the UT3 executable entry uncalled, so run mapped-view, SEH/EH, calling, synchronization and TLS fixtures independently. Record commands, hashes, native identities, logs and exit statuses.

After Phase 1 approval, run a narrowly scoped signed iOS VM feasibility probe in parallel with the macOS development sequence. Test reservation, page size, commit/discard, native Mach-O and physical-device signing using the same relevant primitives with no JIT dependency. Record any iOS architectural blocker separately from the planned Phase 6 application.

## Risks in priority order

| Risk | Early decision or check |
| --- | --- |
| Missing exact CRT or Python install | Check trusted local VC80 files and require both hashes. Resolve pinned packages without changing versions by default. Record Windows input provenance if using it. |
| Fixed VA and zero-fill behavior | Reproduce the audit probe inside the real CLI allocation path across launches. Exercise guest 4 KiB invalidation on 16 KiB mappings. |
| Dispatch wrappers and optimizer assumptions | Inspect Mach-O symbols and run the same-unit, cross-unit and indirect cases with native/exact comparisons. Verify x87/flag and FP edge cases. |
| DXVK assumes unavailable Vulkan bits or ELF loader rules | Audit pinned feature requests before surface integration; test on each device and loader. Preserve query, descriptor and depth semantics when adding a fallback. |
| Engine code tied to platform lifecycle | Build in place across narrow OS interfaces. Move shared files only after callers and tests prove the boundary. |
| iOS memory footprint/signing | Test signed VM early, then measure committed memory, duplicate PE data, textures, queries and pipelines on device before changing budgets. |


## Phase 6 actual progress (2026-11-17)

Authorized Phase 6 is partially implemented: physical-device VM and original runtime self-test passed, as did independent MoltenVK clear/readback/presentation. Actual DXVK D3D9 device creation fails on unsupported robustness2 buffer/null-descriptor features. Gameplay, controls, audio and lifecycle validation remain pending. Remain in Phase 6; do not advance to Phase 7. See [device report](PHASE6_STATUS.md) for actual output, preserved failures and smallest next investigation.


## Phase 6 continuation: explicit D3D9 compatibility

The initial missing-feature failure is superseded by the D3D9 fallback in [D3D9_PORTABILITY.md](D3D9_PORTABILITY.md). Driver capability bits remain false; explicit constant bounds and typed read-only dummy descriptors supply the required D3D9 behavior. Exact ARGB tests, dynamic sampler selection, COM creation/draw/query/Present and 720p/1080p resets pass with Metal API/GPU validation. An ordinary run captured the first real UT3 back buffer on the iPhone. Real-game validation then caught heap aliasing during upload; the dedicated-image correction now passes two real-game frame-capture/exit runs with Metal API and GPU shader validation enabled. The original aliasing assertion did not recur. Existing guest DLL-detach heap-free warnings remain documented. Full Phase 6 gameplay/input/audio/lifecycle remain pending, and Phase 7 is not started.
