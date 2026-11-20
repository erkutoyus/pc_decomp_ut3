# Apple Silicon architecture audit

Current checkpoint: Phase 6 owner acceptance is recorded in [IOS_GAMEPLAY.md](IOS_GAMEPLAY.md); Phase 7 is authorized and its performance results are in [PHASE7_STATUS.md](PHASE7_STATUS.md). Earlier pending/not-started statements below describe historical checkpoints.

Baseline: `f8d1323e4b44c124eba8ecc08364debd32c021a7` (0.5-dev). The upstream implementation is an Android ARM64 host for statically translated Win32 code. The Apple design retains its guest ABI and uses one shared engine with two OS adapters. See [migration gates](MIGRATION_PLAN.md) and [observations](TEST_MATRIX.md).

## Build-time and runtime boundaries

```text
Local Steam PE32 binaries + pinned VC80 runtime files
  -> tools/lift_ut3.py + lift_game.py + reference/pcrecomp
  -> generated C, function declarations, module reports and dispatch table
  -> Clang ARM64 objects + native overrides + Win32 host
  -> Apple ARM64 executable

At runtime:
  Original PE image data -> guest VM -> imports / TLS / DLL initialization
  Guest VA -> native dispatch table -> ARM64 C functions and host imports
  Guest D3D9 COM -> C host -> C++ native DXVK -> Vulkan -> Metal -> CAMetalLayer
```

| Area | Audited implementation and preservation boundary |
| --- | --- |
| Lift and input identity | [lift_ut3.py](../../tools/lift_ut3.py) reads [module pins](../../config/modules.json), verifies original hashes, records rebased hashes, checks reverse relocation, and seeds the decoder from PE metadata and any local catalogs. [lift_game.py](../../tools/lift_game.py) builds reachable functions, handles jump tables and EH owners, emits C chunks and merges address dispatch. Preserve guest VAs, function discovery, unresolved-code diagnostics and module identity. Generated code is absent in this clone and should stay a local build product. |
| CPU and calling conventions | [recomp_types.h](../../engine/runtime/recomp_types.h), [core.c](../../engine/host/core.c), [threads.c](../../engine/host/threads.c), [eh.c](../../engine/host/eh.c). Eight x86 integer registers, flags, segment state, x87 and SSE/MMX state, and x86-width stack slots are exposed by a private runtime ABI. A serialized guest machine saves/restores per-thread state across blocking calls and callbacks. Preserve stack cleanup, register and flag publication, FP conversions and x87 behavior, thread ownership, TEB/PEB, TLS and guest exception unwinding. |
| Guest VM | [memory.c](../../engine/host/memory.c) reserves 4 GiB, uses 32-bit guest offsets, tracks 4 KiB guest pages in 64 KiB allocation granules, and unions subpage permissions on larger host pages. The first granule and synthetic thunk range are guarded, with a default ceiling of `0x7ffe0000` and an optional large-address mode. Preserve the page map, Win32 protection metadata, view semantics, zero on recommit and overflow checks. |
| PE lifecycle | [pe_images.c](../../engine/host/pe_images.c) prepares hash-matched images at runtime from the game path and built-in CRT images. [pe.c](../../engine/host/pe.c) maps PE headers and sections, binds normal and delay imports to lifted calls or synthetic host thunks, tracks module state and handles exports and attach/detach. TLS templates, callbacks and per-thread state must stay matched to the same PE build. PE bytes are data. CPU execution uses signed native text and never jumps into a PE section. |
| Win32 services | [host](../../engine/host) implements kernel, user, registry, file, COM, Winsock, XInput, DirectInput, DirectSound, OpenAL and D3DX boundaries. [files.c](../../engine/host/files.c) and [zipmount.c](../../engine/host/zipmount.c) resolve guest Windows paths against the supplied game root and user-data overlay, with directory and stored-ZIP support. Preserve case behavior, mutable saves/configuration and read-only ownership of original data. |
| Native fast paths | [lift_build.py](../../tools/lift_build.py) owns the link wrap inventory, same-unit rewrites, masks, warm-function list and x87 passes. [features.c](../../engine/host/features.c) also registers dispatch overrides, checks lifted PhysX entries and routes requested effects through the original CPU solver. AI, visibility, render submission, physics, collision, CRT, particle, script VM and query optimizations remain engine code. Keep exact and differential modes and original lifted symbols callable. |
| Graphics | [d3d9_device.c](../../android/host/d3d9_device.c) selects DXVK by renderer setting alongside the existing GLES route. [d3d9_dxvk.c](../../engine/host/d3d9_dxvk.c) owns guest COM objects and thunks. [bridge.cpp](../../engine/dxvk/bridge.cpp) marshals into native COM, owns staging/lock copies and handles window leases. The Android surface and loader are separable from these contracts. See [graphics strategy](GRAPHICS_STRATEGY.md). |
| Audio, input and UI | Preserve guest OpenAL/DirectSound sequencing, XInput and DirectInput state, input queues and release-on-focus behavior. Separate JNI tails from shared C and distinguish real device I/O from guest behavior. The UE3 HUD, camera and menu adjustments are engine behavior even where the Android launcher configures them. |

## Darwin seams

- **Memory and pointer arithmetic.** The Android default host base `0x2000000000` failed on the audited Mac. Evaluate `0x7000000000` as an Apple build-time constant with an exact-address check. The reserve, `ADDR`, `GVA` and any address-provenance path must agree. If a fixed location proves unreliable across signed binaries or iOS devices, publish a per-process reservation base before guest startup and audit every forward and inverse conversion. Measure the generated-code cost before choosing its production form.
- **Commit and release.** On this Mac, `MADV_DONTNEED` retained a sentinel through a protection cycle. Use a checked, zero-fill primitive for whole **owned** anonymous host pages and preserve neighboring guest pages when clearing a subpage. Keep the guest page map coherent on syscall failure. Extend the audit to file-backed/shared views, release, alignment, protection unions and writable-data checks. Never use a destructive fixed mapping to acquire an unowned range.
- **Mach-O and ABI.** ELF `.hidden`, `.pushsection`, the absolute guest-memory symbol and lld `--wrap` do not transfer unchanged. Test a Mach-O data section or generated C data for CRT blobs. Prove direct cross-unit, direct same-unit and indirect native overrides, plus calls to the original bodies. Use the existing compile-time `ADDR` route for the first bounded smoke target if it validates, and track the Android-gated separate-storage/provenance optimizations explicitly.
- **Faults and threads.** `core.c` reads Linux ARM64 `ucontext` fields and has a crash journal. Darwin needs native context extraction and signal chaining with async-signal-safe writes. Keep guest C++ EH separate from host fault reporting. `kernel32.c` uses Linux auxv and ARM timer behavior, `threads.c` uses scheduler affinity and sysfs, and `network.c` has platform socket flags. Qualify monotonic timing, Guest QPC, elapsed/timeout behavior, thread naming, affinity/QoS policy and socket signal behavior with Apple tests.
- **Apple interfaces.** Keep plain-C engine entry and lifetime, game/user paths, monotonic clock, VM, input, event snapshots and window leases. AppKit owns windows, menus and layer setup on the main thread. Keep the guest execution and render worker schedulers separate from that UI thread. UIKit can supply the same contracts with scenes, touch, safe area, suspend/resume and memory pressure. Store platform-specific layer and framework objects behind the host boundary. Size, focus and lifetime changes need explicit handoff to the render owner.

The native CLI is the first Apple entry point. AppKit joins in Phase 2, Vulkan/Metal in Phase 3, then audio and gameplay integration in Phase 4. The Android reference and optimization fixtures stay available throughout.

## Phase 2 ownership

- [Application.m](../../platform/apple/Application.m) owns AppKit activation, menus, file selection, the window and shell diagnostics on the main thread. A dispatch group runs one instance of the startup check through the [C runtime interface](../../engine/host/runtime.h). The group completion returns to the main queue. Quit requested during startup waits for that completion through AppKit's termination reply. The worker restores its fault setup and closes engine diagnostics. The guest address space and loaded module state remain process-owned.
- [GameView.m](../../platform/apple/GameView.m) owns a view-backed `CAMetalLayer` with backing-pixel size and scale updates. The native window and its view are detached during AppKit termination. Device, drawable and swapchain creation enter in Phase 3. [Apple game window guide](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos?changes=l_4&language=objc)
- The view routes physical key positions, sided modifiers and mouse events through the [shared C input API](../../engine/host/input.h). Focus loss releases held keyboard and mouse input and clears their pending snapshot deltas. Game Controller supplies the first extended controller to XInput slot zero. The portable snapshot keeps its byte layout for Win32 callers. Focus loss and disconnect clear the snapshot, and teardown removes callback ownership. [Apple extended gamepad profile](https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad?changes=l_8___5)

## Phase 4 macOS game launch

The graphics-enabled AppKit bundle sends ordinary launches through the lifted game entry. Phase 2 shell checks and Phase 3 renderer diagnostics use their existing validation routes. The Apple target stages the pinned OpenAL Soft CoreAudio dylib alongside DXVK. The shared Win32 OpenAL bridge retains guest pointer validation, device and context tokens, and the existing EAX/EFX routing. An optional mixer callback meter observes the actual CoreAudio buffer. The validated default UT3 configuration selected Generic Software audio.

The shared Crypt32 shim marshals Win32 DATA_BLOBs and registers an Apple protection backend at app startup. UE3 still handles the key entry and validation. The macOS backend keeps the protected payload in the user's Keychain and returns an opaque record token to UE3 for its configuration file. The adapter identity stays fixed for the same macOS account, hostname, and data path, independent of the active network interface.

AppKit's Quit and window close handlers post an atomic exit request to the guest frame hook. The hook verifies the pinned UE3 exit routine's original instruction bytes, then calls it with the orderly, non-force flag. UE3 shuts down and reaches its Win32 ExitProcess shim. The shared shim flushes engine diagnostics and calls back to the AppKit main thread to disconnect input, detach the presentation target, and close the window before process exit. The diagnostic and headless targets keep their existing exit behavior.

## Phase 5 source boundaries

The host, runtime, D3D9 bridge, and portable renderer and audio inputs used on Apple are under `engine/`. AppKit, Metal WSI, Keychain, IOKit and the Apple runtime entry points remain under `platform/apple/`. Android-specific activities, packaging, EGL renderer, WSI and driver code remain under `android/`. The Android and Apple builders share the lifted source transformations and DXVK overlays. Each build produces its own COM bridge artifacts. See the [removal manifest](REMOVAL_MANIFEST.md) for the checked dependency edges.


## Phase 6 implementation boundary (2026-11-17)

The common CMake graph now accepts an iOS target and selects a UIKit WindowScene shell before any AppKit packaging/tests. Shared static game code, ABI, memory bookkeeping and startup remain intact. iOS reserves guest data through public vm_allocate at the measured host base; macOS retains mach_vm_allocate. iOS statically links its MoltenVK slice and injects vkGetInstanceProcAddr through the existing loader callback into signed native DXVK. A development-only diagnostic app exists, not a completed iOS gameplay platform: controls, audio sessions, suspend/resume and memory-pressure policy remain pending. [Measured status](PHASE6_STATUS.md).


## Phase 6 continuation: explicit D3D9 compatibility

The initial missing-feature failure is superseded by the D3D9 fallback in [D3D9_PORTABILITY.md](D3D9_PORTABILITY.md). Driver capability bits remain false; explicit constant bounds and typed read-only dummy descriptors supply the required D3D9 behavior. Exact ARGB tests, dynamic sampler selection, COM creation/draw/query/Present and 720p/1080p resets pass with Metal API/GPU validation. An ordinary run captured the first real UT3 back buffer on the iPhone. Real-game validation then caught heap aliasing during upload; the dedicated-image correction now passes two real-game frame-capture/exit runs with Metal API and GPU shader validation enabled. The original aliasing assertion did not recur. Existing guest DLL-detach heap-free warnings remain documented. Full Phase 6 gameplay/input/audio/lifecycle remain pending, and Phase 7 is not started.


## File-based CD key support (2026-11-18)

Completed on macOS and the physical iPhone: the owner-provided `cdkey.txt` passes the original game validator and reaches Login. A synthetic invalid key is rejected. The Mac file-mode backend prevents legacy Keychain authentication UI while retaining records and restoring the previous interaction setting. Native input/audio/gameplay remain Phase 6 work; Phase 7 is not started. File locations, preserved ABI/validation, exact tests, remaining limitations and evidence are in [CDKEY_FILE.md](CDKEY_FILE.md).


## Phase 6 gameplay continuation (2026-11-18)

The native UIKit keyboard, GameController/XInput bridge and pinned OpenAL Soft RemoteIO backend are implemented. The owner verified keyboard typing/deletion/Done, clear sound and a full offline match with GameSir X5 Lite. The owner also verified correct touch selection, keyboard operation, one-second Keyboard button disappearance, and audible sound/controller recovery after restoring the app. Explicit foreground audio-session/device recovery is implemented; external route changes, interruptions and memory pressure remain unverified. Earlier pending statements above describe previous checkpoints. [Current evidence, exact commands, source boundaries and unresolved issues](IOS_GAMEPLAY.md). Phase 7 has not started.

## Simple builds and final directory cleanup

The owner-authorized root Android removal and two-command Apple build path are documented in [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md). Use [BUILDING.md](../../BUILDING.md) for current beginner instructions; older Android-reference/build statements above describe earlier checkpoints.
