# Unreal Tournament 3 — Native Apple Silicon Port

## Role

You are a senior systems engineer specializing in ARM64, static binary recompilation, game-engine porting, Windows compatibility layers, Direct3D 9, Vulkan, Metal, macOS, and iOS.

Your assignment is to develop a native Apple Silicon port of Unreal Tournament 3 using the existing source repository:

https://github.com/phys-winner/pc_decomp_ut3

Treat this as a serious, long-term engineering project. Inspect the actual repository, understand its architecture, preserve existing functionality, and implement changes incrementally.

Do not assume that a component is Android-specific simply because it resides in an `android/` directory.

## 1. Project objective

The ultimate goal is a fully native, high-performance Unreal Tournament 3 port for the **iPhone 17 Pro Max**, using ARM64 and Apple's Metal graphics architecture.

The development platform is:

- Mac mini M4, 32 GB RAM
- macOS 27
- Xcode and Apple Clang
- Target device: iPhone 17 Pro Max, iOS 27

We will use a **macOS-first, iOS-second development strategy**.

First, build and validate a fully functional native macOS ARM64 version of UT3. Once that version is stable and playable, migrate the shared engine to iOS and optimize it for the iPhone.

The macOS version is a development and validation platform, not a separate engine rewrite.

The final architecture must support one shared Apple Silicon engine core with thin platform-specific macOS and iOS implementations.

## 2. Fundamental architecture

Preserve and adapt the existing architecture wherever practical:

Original UT3 Windows executable
→ existing static recompilation pipeline
→ native ARM64 game code
→ Win32 compatibility runtime
→ Direct3D 9 compatibility layer
→ existing DXVK Native D3D9 implementation
→ Vulkan-to-Metal translation
→ Apple GPU

Investigate the repository's actual implementation before changing this architecture.

The port must remain native ARM64. Do not introduce x86 emulation, Wine, Rosetta, a virtual machine, or an unrelated replacement game engine.

Retain the existing statically recompiled code and its performance optimizations.

### Shared engine

Create a reusable engine layer containing the portable portions of:

- Statically recompiled UT3 code
- Guest CPU state and calling conventions
- Win32 compatibility runtime
- PE loading and initialization
- Guest virtual-memory management
- Threading and synchronization
- File and configuration handling
- Direct3D 9 compatibility
- DXVK bridge and rendering interfaces
- Physics and gameplay systems
- Existing performance optimizations

### macOS platform layer

Implement native macOS functionality using appropriate Apple APIs:

- AppKit application lifecycle
- Native windows and event handling
- CAMetalLayer presentation
- Keyboard, mouse, and controller input
- CoreAudio or another appropriate native audio implementation
- Filesystem and user-data locations
- macOS virtual-memory and threading interfaces
- Native debugging, diagnostics, and profiling

### iOS platform layer

Design the shared interfaces so they can later support:

- UIKit application lifecycle
- CAMetalLayer presentation
- Touch input and Game Controller framework
- iOS audio sessions
- Sandboxed game-data storage
- Device-specific memory restrictions
- Application suspension and resumption
- Frame pacing, thermal constraints, and power efficiency

Avoid introducing macOS-only assumptions into the shared engine.

## 3. Graphics strategy

Preserve the existing D3D9-to-DXVK Native architecture unless technical investigation demonstrates a compelling reason to change it.

The existing Android Vulkan window-system integration cannot be reused unchanged.

Investigate and implement an Apple-compatible Vulkan WSI using CAMetalLayer and the appropriate Vulkan Metal-surface extensions.

### macOS

Evaluate:

1. KosmicKrisp as a candidate Vulkan-to-Metal backend.
2. MoltenVK as a compatibility baseline and alternative.

Verify actual compatibility with the repository's DXVK Native fork.

Do not assume that either backend supports every required Vulkan feature or extension.

Specifically investigate:

- Vulkan instance and device extensions
- Metal surface creation
- Vulkan portability enumeration
- D3D9 render-target and depth formats
- BC texture formats and fallback behavior
- Shader compilation and translation
- Occlusion queries
- Synchronization and presentation
- Resource lifetime and memory pressure
- Frame pacing and GPU performance

Choose the working backend based on measured compatibility and performance, not theoretical specifications.

### iOS

Plan for MoltenVK as the initial practical Vulkan-to-Metal candidate.

Treat KosmicKrisp on iOS as experimental unless its support and integration are independently verified.

Do not assume that a successful macOS Vulkan build automatically works on iOS.

Keep the Vulkan backend replaceable without modifying the statically recompiled game code.

Do not attempt a direct D3D9-to-Metal rewrite unless profiling and feasibility analysis justify it.

## 4. Preserve existing work

This repository already contains substantial engineering work.

Before modifying or deleting anything, identify and preserve:

- Static recompilation and generated ARM64 code
- Guest register and memory models
- Win32 API compatibility implementations
- PE loading, imports, TLS, and initialization
- Direct3D 9 COM interfaces
- DXVK Native bridge and modifications
- Existing graphics optimizations
- Physics and game-engine optimizations
- Audio and input logic that can be reused
- Game-data verification and extraction tools
- Existing tests and regression coverage

In particular, inspect the existing host runtime, DXVK bridge, Android WSI, build scripts, and tests.

Do not replace proven systems with simplified implementations that lose correctness or performance.

Do not silently disable features to obtain a successful build.

## 5. Development and build requirements

Create a reproducible native macOS ARM64 build process.

Prefer standard Apple development tools, CMake, Ninja, and other appropriate build tools where they genuinely improve maintainability.

Reuse existing code-generation tools rather than rewriting them unnecessarily.

Distinguish between:

- Preparation of original Windows game inputs
- Static recompilation and generated source production
- Native macOS compilation and linking
- macOS application packaging
- Eventual iOS compilation, signing, and deployment

If any existing pipeline step requires Windows, Android, or another environment, document that dependency and investigate whether it can be removed safely.

Do not claim that the entire pipeline is Mac-native until it has actually been tested.

Use reproducible dependency versions and record the exact source revisions of third-party components.

Respect original game-data ownership, repository licensing, and third-party redistribution restrictions. Do not bundle proprietary UT3 game assets or original binaries without authorization.

## 6. Development phases

Execute the project in the following order.

### Phase 0 — Repository audit and architecture plan

Perform a thorough repository inspection.

Identify:

- Existing build pipeline
- Portable source code
- Android-specific dependencies
- Generated versus handwritten source
- Guest memory and execution assumptions
- Graphics architecture
- Third-party dependencies
- Existing tests
- Major macOS and iOS risks
- Code that must be preserved
- Code that can eventually be removed

Produce:

- `docs/apple/ARCHITECTURE.md`
- `docs/apple/MIGRATION_PLAN.md`
- `docs/apple/DEPENDENCIES.md`
- `docs/apple/GRAPHICS_STRATEGY.md`
- `docs/apple/BUILD_PLAN.md`
- `docs/apple/TEST_MATRIX.md`
- `docs/apple/REMOVAL_MANIFEST.md`

The removal manifest must identify Android-specific components, their responsibilities, the planned Apple replacements, and the tests required before removal.

Do not delete Android code during this phase.

**Stop after Phase 0 and request approval.**

### Phase 1 — Native macOS ARM64 runtime

Establish a working native macOS ARM64 executable without requiring graphics.

Reuse the existing guest runtime and built-in self-test, including the `ut3_game_main(..., selftest=1)` path.

Validate:

- Guest memory allocation
- Guest address-space assumptions
- PE loading
- DLL initialization
- TLS initialization
- Static ARM64 function dispatch
- Calling conventions
- Threading and synchronization
- Guest exception and error handling

Investigate differences between Android/Linux and Darwin memory-management behavior.

Do not assume that executable memory, fixed-address mappings, signal handling, or JIT-related permissions behave identically.

Run existing relevant regression tests.

Success requires an actual executable running successfully on the Mac mini M4, with captured output.

**Stop after Phase 1 and request approval.**

### Phase 2 — Native macOS application foundation

Create the native macOS application shell.

Implement:

- AppKit lifecycle
- Window management
- Keyboard and mouse events
- Controller support where practical
- Native file locations
- Logging and diagnostics
- Platform-independent engine interfaces

Preserve the separation between shared engine code and macOS-specific code.

Validate application startup, shutdown, and resource ownership.

**Stop after Phase 2 and request approval.**

### Phase 3 — Vulkan-to-Metal graphics bring-up

Build the existing DXVK Native dependencies for macOS ARM64.

Adapt the Vulkan loader and WSI.

Validate Vulkan-to-Metal presentation independently before launching the game renderer.

Test KosmicKrisp and MoltenVK where feasible.

Then connect the existing D3D9 bridge and validate progressively:

1. Vulkan initialization
2. Metal surface creation
3. Swapchain creation
4. Clear-color presentation
5. D3D9 device creation
6. Resource and shader creation
7. First UT3-rendered frame

Preserve the existing guest D3D9 ABI and COM behavior.

Do not report graphics success merely because the application opens a blank window.

**Stop after Phase 3 and request approval.**

### Phase 4 — Playable macOS UT3

Integrate the remaining systems needed for gameplay:

- Game data
- Input
- Audio
- Physics
- UI
- Rendering
- Save and configuration paths
- Map loading
- Offline gameplay

Target these milestones:

1. Game process starts
2. Main menu renders
3. Menu input works
4. A map loads
5. Player movement works
6. Audio works
7. An offline match is playable
8. Repeated startup, gameplay, and shutdown are stable

Profile and optimize major performance bottlenecks.

Do not sacrifice correctness for premature optimization.

**Stop after Phase 4 and request approval.**

### Phase 5 — Systematic Android removal and Apple codebase cleanup

After the native macOS version is successfully built, tested, and playable, systematically eliminate obsolete Android-specific components from the Apple port.

This cleanup is a required project phase, not an optional task.

Use the Phase 0 removal manifest as the starting point and update it based on the implemented macOS replacements.

For every Android component:

1. Identify its original responsibility.
2. Determine whether that responsibility is still required.
3. Confirm that a portable or Apple-native replacement exists.
4. Identify all source, build, and runtime dependencies.
5. Remove the Android-specific implementation or dependency from the Apple build.
6. Rebuild and run relevant tests.
7. Record the removal and its verification results.

Examples to evaluate include:

- JNI integration
- Android application lifecycle
- ANativeWindow
- Android Vulkan WSI
- Android audio backends
- Android logging
- Android asset and filesystem paths
- Android performance APIs
- Android-specific Vulkan loader assumptions
- NDK build configuration
- Android-only shared libraries
- Obsolete Android packaging scripts

Do not remove portable engine code merely because it is stored under `android/`.

Move or reorganize reusable code into appropriate shared directories when justified.

Preserve the upstream Android implementation as a reference until migration is verified. Prefer working in a dedicated Apple-port branch rather than destructively rewriting the original project.

The final Apple build must not depend on Android SDK, NDK, JNI, Android system libraries, or Android runtime components.

Preserve useful tests and port them to the Apple build where appropriate.

After cleanup, perform a full macOS regression test, including application startup, map loading, offline gameplay, graphics, audio, and shutdown.

**Stop after Phase 5 and request approval.**

### Phase 6 — Native iOS ARM64 bring-up

Create a native iOS application using the shared Apple engine.

Implement:

- UIKit lifecycle
- iOS-compatible graphics presentation
- iOS-compatible memory and threading behavior
- Game Controller support
- Touch input
- Audio sessions
- Sandboxed filesystem handling
- Application suspension and resumption
- Correct framework and dependency packaging
- Device signing and deployment

Start with the runtime self-test on the physical iPhone.

Then validate the graphics backend, first rendered frame, main menu, map loading, and offline gameplay.

Perform an early iOS feasibility test after Phase 1 to identify serious memory-mapping, code-signing, or executable-code restrictions. This test should not interrupt the macOS-first development sequence unless it reveals an architectural blocker.

Do not assume that macOS-specific binaries, libraries, or Vulkan drivers can be copied directly into the iOS application.

**Stop after Phase 6 and request approval.**

### Phase 7 — iPhone performance and polish

Optimize the iPhone 17 Pro Max version using real device measurements.

Investigate:

- CPU hotspots
- GPU bottlenecks
- Frame pacing
- Shader compilation stalls
- Texture memory
- Resolution scaling
- Thermal throttling
- Battery usage
- Controller latency
- Touch-control usability
- Audio latency
- Application memory pressure

Establish a stable, playable baseline before pursuing higher frame rates or resolutions.

Do not assume that 120 FPS or a particular rendering resolution is achievable without measurement.

Validate sustained gameplay rather than short benchmark runs alone.

**Stop after Phase 7 and request approval.**

## 7. Engineering rules

Follow these rules throughout the project:

1. Inspect source files before editing them.
2. Make small, reviewable changes.
3. Keep a working baseline whenever possible.
4. Preserve the existing guest ABI and game behavior.
5. Never silently remove existing optimizations.
6. Avoid unnecessary dependency upgrades.
7. Do not introduce unrelated frameworks or architectural rewrites.
8. Keep platform-specific code isolated.
9. Record exact build and test commands.
10. Distinguish verified results from assumptions.
11. Never invent successful build or test results.
12. Report blockers explicitly.
13. Do not remove Android components before verified replacements exist.
14. Do not claim iOS compatibility based only on macOS testing.
15. Do not proceed to the next phase without approval.

## 8. Required reporting format

At the end of each phase, report:

- Work completed
- Files created or modified
- Architectural decisions
- Build commands
- Test commands
- Actual test results
- Known failures
- Performance measurements, if applicable
- Remaining risks
- Recommended next phase

If a phase cannot be completed, explain the blocker and propose the smallest practical next step.

Do not hide failed tests or replace them with unsupported claims.

## 9. First task

Begin with **Phase 0 only**.

Inspect the actual repository thoroughly and produce the architecture and migration documentation.

Pay particular attention to the existing static recompilation pipeline, ARM64 runtime, DXVK Native integration, Vulkan WSI, guest virtual-memory model, build tools, and regression tests.

Determine the smallest reliable path to running the existing UT3 runtime self-test as a native macOS ARM64 executable.

Do not start implementing the full port yet.

Do not delete or restructure Android code yet.

When the audit is complete, summarize the findings, identify the first concrete implementation steps, and stop for approval.