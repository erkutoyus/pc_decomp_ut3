# iOS D3D9 correctness fallback — Phase 6, 2026-11-17

## Scope and decision

The pinned MoltenVK 1.4.2 slice on the physical A19 Pro reports `robustBufferAccess2=0` and `nullDescriptor=0`. These values remain false. We do not advertise unsupported Vulkan features or implement a generic Vulkan robustness2 layer. Instead, the existing DXVK Native 2.4.1 D3D9 path now implements the D3D9 behavior it needs explicitly. D3D10/11/8 remain outside this renderer build, as before.

`tools/d3d9_portability.py` applies an exact-context overlay after the existing shared and Apple overlays. Only `tools/build_dxvk_ios.py` invokes it. macOS, KosmicKrisp, the Android reference, the guest COM ABI and static game code are unchanged by this fallback. The native driver feature path remains usable. Source hashes and the resulting unsigned dylib hash are recorded in `build/apple/phase6/dxvk-portability/receipt.json`.

## Constant access

The existing DXSO fallback already selected zero for out-of-range relative constants, but did so **after** loading from the original index. That is insufficient for Metal: a later selection cannot make an unsafe load safe. The overlay performs an unsigned bounds comparison before `OpAccessChain`, selects a valid index (zero) for the actual load, and selects a typed zero for an invalid result. Negative indices fail the unsigned test. Float and integer constant counts are distinguished. The existing D3D9 constant layouts, copy logic and full constant-range fallback remain in use.

The native robustBufferAccess2 path retains its existing behavior. Buffer slice alignment continues to respect the Vulkan minimum alignments. This is not a promise to supply generic robustness2 for arbitrary storage shaders or invalid draw buffer ranges.

## Unbound descriptors

D3D9's existing `SpecSamplerNull` logic supplies its required null-texture color, including alpha. The backend still needs valid descriptors for every statically used shader binding, even in an inactive branch. The overlay supplies initialized, device-owned read-only dummy textures of matching dimensionality and comparison type. Color/depth and 2D/3D/cube sampler variants receive distinct slots, including when the compiler emits dynamic type-selection branches. A compile-time assertion pins the slot stride. Fixed-function bindings keep their original slots. Internal array-view descriptors are also represented by valid typed views.

Dummy images are cleared and transitioned through the existing DXVK context, with initialization submitted before the command list that uses them. Device-owned strong references keep images/views/samplers live. Missing uniform and vertex buffers receive existing zero-buffer storage; missing vertex streams use zero stride. The Vulkan feature flags remain truthful throughout.

A shared writable dummy would not implement null-descriptor stores/atomics correctly. Null storage buffers/images, texel descriptors and other unhandled types therefore fail explicitly before the Vulkan descriptor update. This build does not claim generic Vulkan nullDescriptor support, D3D11 compatibility, or complete coverage of every legal D3D9 operation. Real game coverage remains a separate milestone.

## Metal heap aliasing discovered during validation

The first ordinary UT3 run captured and presented a real 640x480 back buffer. Retesting with `MTL_DEBUG_LAYER=1` and `MTL_SHADER_VALIDATION=1` then aborted at a Metal aliasing assertion. The crash stack identifies `MVKCmdBufferImageCopy::encode` and `copyFromBuffer:...toTexture:...`. Evidence is retained in `metal-alias-crash.ips` and `ut3-frame-validation-shutdown-device.log` under `build/apple/phase6/`.

DXVK's chunk allocator creates a buffer spanning its suballocation heap. Under MoltenVK, that buffer and optimal textures in the same heap are aliasing Metal resources, even when the transfer uses distinct subranges. Metal disallows the buffer-to-texture blit in this case. The iOS overlay therefore requests **required dedicated memory for optimal images on MoltenVK**, preventing retry through the mixed heap on allocation failure. Other driver paths and buffer suballocation retain their behavior. Heap support, compressed formats and alias-capable views have not been globally disabled.

This trades image packing efficiency for a correct Metal resource arrangement. Allocation count, padding overhead and full-map memory pressure must be measured in the remaining Phase 6 gameplay work before treating this as a final allocation policy. A future segregated allocator or a verified driver fix may recover packing efficiency; correctness must remain the regression criterion.

## Actual test evidence

Logs below are local artifacts under `build/apple/phase6/`.

| Test | Actual result and evidence |
| --- | --- |
| Original failure | `d3d9-device.log`: unsupported robustness2 flags, CreateDevice HRESULT 8876086a. |
| Scoped fallback device creation | PASS: `portability-final-device.log`; no fake feature bits. |
| Bound and null 2D/volume/cube sampling | PASS via GPU pixel readback. |
| Null-to-bound texture rebinding | PASS via exact ARGB readback in `portability-alpha-validation-device.log`. |
| Relative constants at 0, -1 and 4096 | PASS: valid red including alpha, invalid accesses all zero including alpha. |
| Dynamic sampler branches | PASS: repeat with `d3d9.forceSamplerTypeSpecConstants=True`, `portability-alpha-dynamic-validation-device.log`. |
| Depth/BC format checks, SM3 draw, occlusion, Present, 720p/1080p resets | PASS in both RGBA runs. |
| Metal API and GPU shader validation for fixtures | Enabled explicitly in both RGBA runs; tests returned status 0 with no reported Metal validation failure. Final reproduced build with dedicated images also passed all eight ARGB tests and COM/presentation/reset checks in `dedicated-final-d3d9-validation-device.log`. |
| Original UT3 entry point | First actual frame captured at 26.192 seconds in the ordinary run, showing the CD-key screen. `ut3-game-device.log`, `ut3-first-frame-iphone.ppm` and `.png`. |
| Real game with Metal validation | Initial heap-aliasing failure preserved. Final reproduced dedicated-image build: PASS on two separate launches, capture/Present/engine-thread exit, process code 0. `dedicated-final-ut3-validation-device.log`, `dedicated-repeat-ut3-validation-device.log`. No reported Metal API/GPU validation failure. |
| macOS regression | Final rebuild and 7/7 CTest pass, `portability-macos-final-tests.log`. |

The final game captures occurred at 17.992 seconds and 7.245 seconds (separate launches, caches differ). These are diagnostic startup times, not a controlled performance comparison. The validated image is `build/apple/phase6/ut3-first-frame-iphone-validated.png`, converted without alteration from `dedicated-final-ut3-userdata/ut3-first-frame.ppm`. Both show the original CD-key screen during its initial presentation. The full sandbox evidence is in `dedicated-{final,repeat}-ut3-userdata`.

Both exits retain 1,472 guest heap-free warnings during DLL detach after the CRT image is restored/re-attached. The same warning class is present in Phase 5 macOS `repeat1-console.log`, `repeat2-console.log` and offline logs. This is an unresolved shared-runtime teardown diagnostic; do not interpret process exit 0 as complete resource-ownership correctness. No heap checks were suppressed or weakened. The final app exits after the diagnostic frame, so it is not left consuming GPU resources on the phone.

The initial fixture attempted an SM1 shader and encountered the pre-existing guest bridge boundary rejection (`SM1 shader boundary not implemented`). That failure is preserved in `portability-fixture-device.log`. The final fixture instead tests dynamic selection through SM3 and the existing compiler option. It does not claim to add SM1 guest ABI support. An earlier fixture also caught an unhandled array-view fallback; typed array views were added and the final presentation/reset fixture passed.

No Vulkan validation layer was run on iOS; Metal API and GPU shader validation are separate checks, not substitutes for Vulkan validation. No complete game-input, audio, offline-match, suspension/resumption, or thermal-performance result is claimed. The first-frame diagnostic explicitly uses `-nosound` and does not bypass the original CD-key screen. No Phase 7 work is included.

## Reproduction

Use [BUILD_PLAN.md](BUILD_PLAN.md), Phase 6 commands, with DXVK build directory `build/apple/phase6/dxvk-portability`. Build and package the app against its dylib. The owner-provided `Binaries`, `Engine` and `UTGame` directories must be in `Documents/Game` for a real launch; only `Binaries` is needed by the existing self-test. No assets are bundled with source.

Launch the signed app using `xcrun devicectl device process launch` with the existing paired device and bundle ID `org.ut3.port.ios.probe`:

- `-- --validate-d3d9`: exact ARGB tests and existing COM fixture.
- `-- --validate-d3d9 --dynamic-samplers`: same tests with dynamic sampler selection.
- `-- --validate-game`: actual UT3 entry, captures first non-uniform back buffer through the existing bridge.
- `-- --validate-game --exit-after-frame`: clear previous capture, then request the original guest exit on the engine thread after a new capture.

For validation use `--environment-variables '{"MTL_DEBUG_LAYER":"1","MTL_SHADER_VALIDATION":"1"}'` before the bundle identifier. Preserve console output and copy `Documents/UserData` before subsequent launches overwrite logs. The unmodified initial failure and ordinary first-frame evidence remain in their own directories.

## Primary references

- [Khronos robustness guide](https://github.khronos.org/Vulkan-Site/guide/latest/robustness.html): buffer bounds and null-descriptor guarantees.
- [MoltenVK robustness2 buffer issue](https://github.com/KhronosGroup/MoltenVK/issues/2447) and [nullDescriptor issue](https://github.com/KhronosGroup/MoltenVK/issues/2650): upstream missing functionality; capability decisions here are based on actual device queries.
- [MoltenVK configuration](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Configuration_Parameters.md): heap support is required by some image-view features; it was preserved.
- [Pinned-version MoltenVK transfer implementation](https://github.com/KhronosGroup/MoltenVK/blob/v1.4.2/MoltenVK/MoltenVK/Commands/MVKCmdTransfer.mm): buffer/image Metal encoding path, matching the observed crash stack.

## Final receipt and verification

The successfully re-prepared build retains DXVK revision `0cf05780abd7250c2cd713b7749cf32180157cf5` and has unsigned dylib SHA-256 `3db56c4bcb1598bc403ba20f511bdbf13f57ac03fb004021cc6dbb1ccd6928f1`. The unsigned app staging copy matches this receipt. The signed app installed for the final tests is `build/apple/phase6/reproduced-device/Unreal Tournament 3.app`; signing changes its embedded dylib signature bytes. Overlay source hashes match `receipt.json`. No dependency upgrade was required. `git diff --check` passed. The final macOS build and 7/7 CTest results remain in `portability-macos-final-{build,tests}.log`.
