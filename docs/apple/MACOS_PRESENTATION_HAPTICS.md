# macOS build 14 — presentation, backend comparison and controller haptics

2026-11-23. The owner reported tearing and lower perceived performance than iOS, and requested macOS gamepad vibration.

## Changes delivered

- Native AppKit startup defaults to `d3d9.presentInterval = 1` and a 60 FPS ceiling, matching the iOS frame-rate target. Normal gameplay logs confirm FIFO before the first accepted Present. The constructor can log an initial immediate-mode swapchain, which is replaced on the first D3D9 Present when DXVK applies the sync interval.
- The **Graphics** menu selects KosmicKrisp or MoltenVK and toggles Vertical Sync. Preferences take effect after restart. KosmicKrisp remains the default. Explicit `DXVK_CONFIG`, `UT3_FPS_LIMIT`, `VK_DRIVER_FILES`/`VK_ICD_FILENAMES` overrides retain precedence for diagnosis. The native VSync override takes precedence over the original game's presentation interval; use Graphics to control it.
- The pinned SHA-1 rotate transformation now defaults on for both Apple targets and is explicitly selected by both beginner build scripts. Before this work the Mac cache was OFF while iOS was ON. The M4 differential fixture validates the transformation. No numerical claim about its effect on whole-match performance follows from the backend comparison; both compared backends used it.
- The confirmed iPad controller haptics implementation moved into `platform/apple/ControllerHaptics.{h,m}` and is used by AppKit and UIKit. macOS now owns the same finite-duration left/right controller events, fresh motor mailbox, active-window polling and stop/reconnect cleanup. The original waveform generator and player vibration preference remain intact.
- The existing D3D9-only MoltenVK portability overlay is now also applied by `tools/build_dxvk_macos.py`. It implements constant bounds and typed unbound read descriptors while keeping actual Vulkan feature bits truthful. Native robustness2 is still enabled when supported; MoltenVK image allocations retain the existing dedicated-image correctness path. No dependency upgrade, direct Metal renderer, emulation or guest ABI change was introduced. The renderer receipt records overlay hashes.
- Both backends remain packaged. Build 14 was copied to `/Applications/Unreal Tournament 3.app`; the previous installed app is preserved locally at `build/apple/cleanup/installed-macos-before-build14.app`. The packaged copy remains `dist/macos/Unreal Tournament 3.app`. Personal game data stays outside the app.

[Vulkan specifies that immediate mode may tear and FIFO does not](https://docs.vulkan.org/refpages/latest/refpages/source/VkPresentModeKHR.html). [Apple documents the same tradeoff for CAMetalLayer display synchronization](https://developer.apple.com/documentation/quartzcore/cametallayer/displaysyncenabled?language=objc). FIFO selection verifies the synchronization policy; physical observation is a separate owner check.

## M4 comparison

Same native executable/DXVK library, 1920×1080, 60 FPS ceiling, FIFO, Deck, eight-player spectator startup, fixed seed, no time/score limit, isolated copies of the same profile. Application DXVK/state caches were removed for each backend's first run and retained for its repeat. System Metal/compiler caches were not cleared. Vulkan and Metal validation were disabled for timing. Each sample ran 70 seconds after its first accepted Present, followed by an orderly AppKit shutdown. No build jobs or regression suites ran during these captures.

Metric: accepted Vulkan Present gaps, **not GPU completion or display scanout**. Initial window is 0–10 seconds after first accepted Present; steady window is 30–65 seconds. Bot/camera activity and draw counts vary despite equal settings, so this is a practical gameplay comparison, not identical GPU work or a statistically controlled driver ranking.

| Backend/run | Launch to first accepted Present | Steady presents/s | Steady p99 gap | Steady maximum gap | Initial p99 gap |
| --- | ---: | ---: | ---: | ---: | ---: |
| KosmicKrisp, fresh app caches | 13.26 s | 59.97 | 20.77 ms | 38.24 ms | 164.87 ms |
| KosmicKrisp, repeat | 6.13 s | 60.00 | 20.34 ms | 30.05 ms | 83.84 ms |
| MoltenVK, fresh app caches | 29.95 s | 59.97 | 18.01 ms | 33.34 ms | 283.06 ms |
| MoltenVK, repeat | 6.10 s | 53.14 | 28.99 ms | 489.88 ms | 183.58 ms |

**Confound:** the controller was connected during the MoltenVK repeat (its capability event is in that log). That run cannot isolate backend effects from hotplug work. It is retained rather than discarded or reported as a clean driver-only result. The fresh MoltenVK run reached a stable 60-present/s window but had a slower first frame and heavier initial stalls. These observations do not justify promising that swapping drivers fixes all hitches or that KosmicKrisp is universally slower. Keep KosmicKrisp as the working default and expose MoltenVK as an alternative. A subsequent camera-controlled, no-hotplug paired study is needed for a stronger performance ranking.

A native window screenshot inspection confirmed that MoltenVK rendered the actual Deck geometry and spectator HUD, rather than a blank window. All four sessions logged actual map loading/match startup and exited with guest status 0 and no worker outstanding. Raw logs, CSVs and summaries: `build/apple/cleanup/mac-backends/`; harness: `build/apple/cleanup/compare_mac_backends.py`. First-Present times are harness wall times and have polling resolution of approximately 0.5 s.

## Graphics correctness and known failure

The extended D3D9 fixture now runs on macOS as well as iOS, including bound/null/rebound 2D, null volume/cube textures and in-range/negative/4096-relative vertex constants with exact GPU pixel readback. It also covers depth/BC formats, SM3 draw, precise occlusion and 720p/1080p resets/presentation.

- **MoltenVK PASS**, with Vulkan validation and Metal API/shader validation enabled. All exact readbacks, 56310 occlusion samples and resolution resets passed; worker status 0.
- **KosmicKrisp FAIL** on the first bound-texture readback: expected `ffffffff`, received `00000000`. The same failure reproduced with the previously shipped native DXVK library and with sampler specialization forced. It predates this change; later fixture cases were not run after that failure. No Vulkan validation error explained it. The real UT3 maps still rendered/presented during the separate gameplay runs. This is a known compatibility limitation, not a passing full graphics regression and not evidence that every UT3 frame is wrong.

Relevant logs: `mac-molten-d3d9.log`, `mac-krisp-d3d9.log`, `mac-krisp-original-d3d9.log` under `build/apple/cleanup/`; the specialization experiment is `/tmp/ut3-mac-krisp-specialized-d3d9.log`. Future work should isolate the KosmicKrisp texture/readback discrepancy before treating that driver as universally correct.

## Build and regression commands

```sh
build/apple/venv/bin/python -B tools/build_dxvk_macos.py \
  --source build/apple/phase3-inputs/dxvk-upstream \
  --sdk build/apple/phase3-inputs/VulkanSDK/macOS \
  --meson build/apple/venv/bin/meson --build build/apple/macos-dxvk --jobs 8
cmake -S . -B build/apple/macos -DUT3_APPLE_SHA1_ROTATES=ON
cmake --build build/apple/macos --parallel 8
cmake --build build/apple/ios --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
build/apple/macos/ut3-runtime-selftest --game /Volumes/NVME512/Github/UT3 \
  --data build/apple/cleanup/mac-build14-selftest --selftest
build/apple/venv/bin/python -B -m unittest \
  tests.test_apple_rotates tests.test_package_ipa tests.test_apple_frame_analysis
build/apple/venv/bin/python -B tools/check_apple_dependencies.py \
  --build build/apple/macos --dxvk-build build/apple/macos-dxvk \
  --openal-build build/apple/macos-openal
```

- Native CTest: **17/17 PASS**, including the SHA-1 differential, data/config preservation, pointer and motor-lifetime checks. Original self-test: PASS, process exit 0.
- Selected Python regressions: **11/11 PASS**.
- iOS compilation after moving shared haptics: PASS. The already confirmed iPad IPA was not replaced; no new iOS device result is claimed.
- Dependency audit: exit 0; 2107 Mac, 143 DXVK and 104 OpenAL commands checked with recorded dependencies; no Android build/runtime dependency introduced.
- Native AppKit build 14: compile/link PASS; packaged with both runtime ICDs; ad hoc codesign verification PASS. `git diff --check`: PASS.
- Initial manual DXVK invocation mistakenly pointed to the header-only reference tree and failed before compilation; using the original pinned full checkout succeeded. An overlapping old configuration regeneration restored the Mac SHA-1 cache to OFF; a subsequent sequential configuration and rebuild explicitly confirmed ON before all timed runs. These setup failures were corrected rather than counted as successful builds.
- Pinned third-party DXVK compilation retains its existing warning set; no validation error or feature requirement was suppressed to pass the MoltenVK fixture.

Build transcripts are `mac-haptics-dxvk-build.log`, `mac-shared-ios-build.log`, `mac-sync-configure-final.log`, `mac-build14*.log`, `mac-haptics-python-tests.log` under `build/apple/cleanup/`.

## Physical controller and normal-launch result

The installed build detected Wireless Controller with separate Left Handle/Right Handle localities. In an isolated Morbias firing fixture, UT3 generated motor strengths **37712 / 31426**, followed by `[apple-haptics] first game rumble submitted to controller ... (separate handles)`. The owner explicitly confirmed feeling vibration on the Mac. The fixture uses synthetic controller trigger input only; haptics originate from UT3, not a replacement shot/damage generator.

That fixture exited with guest status 0 and no worker outstanding. The installed app was reopened normally with synthetic input and validation disabled. Its normal log confirms a first real accepted Present and FIFO presentation. The owner subsequently confirmed that tearing is absent, vibration works and performance is good. This physical confirmation is separate from the accepted-Present measurements and does not establish the absence of every possible hitch.
