# macOS build 15 — cursor reach after resolution changes

2026-11-23. The owner confirmed build 14 has no tearing, working vibration and good performance, then reported that changing resolution prevented the mouse reaching the bottom of the screen.

## Root cause and change

The native D3D9 bridge updated macOS's reported guest screen size while preparing a Reset, using `void_input_set_screen_size`. That function preserves the existing ClipCursor rectangle. When the old clip covered the full old screen, increasing the reported screen size first made the old clip look deliberately smaller. The later resize helper could no longer recognize/migrate it. Input therefore remained limited to the previous resolution even though AppKit already mapped absolute mouse positions to the current backbuffer correctly.

`engine/dxvk/bridge.cpp` now uses the same successful-CreateDevice/Reset publication path for both Apple platforms: `void_input_resize_surface` updates the screen and migrates an old full-surface clip together. The earlier macOS-only screen mutation was removed; non-Apple behavior is retained. Deliberately smaller clips remain intact. Publication remains after successful D3D9 calls. No mouse Y-direction, sensitivity, relative movement or guest ABI changes were needed. iOS retains its previous resize behavior.

## Actual validation

- Mac compile/link PASS; build number 15. No change to the haptic channel mapping after the owner's isolated motor check (see CONTROLLER_HAPTICS.md).
- Native CTest **17/17 PASS**. The existing real input fixture covers migration of full-surface clips and preservation of smaller custom clips.
- Extended actual D3D9 fixture on MoltenVK with Vulkan and Metal API/shader validation: PASS. At 1280×720, 1920×1080, 640×480 and 1280×1024, Reset updated the full clip to the new dimensions and a real production input motion reached the exact bottom-right guest pixel. Backbuffer queries, clear and Present also passed; worker status 0. The prior bound/null sampler and constant-bounds readbacks still passed. This does not resolve the separately documented KosmicKrisp texture-fixture failure.
- iOS native compile/link PASS after the shared bridge change. The existing confirmed iPad IPA was not replaced; no new iOS device result is claimed.
- Packaged Mac signature verification PASS; `git diff --check` PASS.
- Installed `/Applications/Unreal Tournament 3.app` reports build 15. Build 14 is preserved at `build/apple/cleanup/installed-macos-before-build15.app`.
- The owner applied 1280×720 followed by 1920×1080 in the normal installed game and explicitly confirmed bottom/right menu reach works at both resolutions. The normal console records successful backbuffer/input-surface transitions 1920×1080 → 1280×720 → 1920×1080.

Commands:

```sh
cmake --build build/apple/macos --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
cmake --build build/apple/ios --parallel 8
# Launch AppKit with the pinned MoltenVK ICD and validation enabled:
# --game /Volumes/NVME512/Github/UT3 --data <isolated-data> --validate-d3d9
```

The D3D9 fixture in `platform/apple/d3d9_probe.c` establishes a 640×400 full clip and validates both larger and smaller Resets against real input state. Local transcripts: `build/apple/cleanup/mac-build15{,-tests,-reset,-normal,-package}.log` and `ios-shared-build15.log`. The beginner build command and output location are unchanged; `dist/macos/Unreal Tournament 3.app` is the same packaged build 15. The iOS linker retains its pre-existing duplicate MoltenVK-library warning.
