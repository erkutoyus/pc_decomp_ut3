# Unreal Tournament 3 — native Apple Silicon port

Native ARM64 UT3 using the existing static recompilation, shared Win32 runtime, DXVK Native D3D9 and Vulkan-to-Metal presentation. macOS uses AppKit; iOS uses UIKit and MoltenVK. This is not Wine, Rosetta, x86 emulation or a replacement game engine.

## Build

On an Apple Silicon Mac with Xcode and the prerequisites in [BUILDING.md](BUILDING.md):

```sh
./build_macos.sh "/path/to/UT3"
./build_ios.sh "/path/to/UT3"
```

The outputs are `dist/macos/Unreal Tournament 3.app` and `dist/ios/Unreal Tournament 3.ipa`. The iOS IPA is unsigned for SideStore to sign; copy your original game files through Finder after installation. **Game assets and CD keys are not included.**

[Complete beginner build/install instructions](BUILDING.md) explain one-time setup, game-folder layout, caching and troubleshooting.

## Status

The M4 macOS port and iPhone 17 Pro Max port have rendered maps and offline gameplay. Owner testing confirmed GameSir X5 Lite input, audio, keyboard, touch-to-mouse, saved resolution and foreground audio/controller recovery. The iPhone target is currently 720p at 60 FPS, with 1080p available. Startup/package and pipeline-compilation hitches remain; no battery-life or all-stutters-fixed claim is made.

- [Architecture](docs/apple/ARCHITECTURE.md)
- [Migration plan](docs/apple/MIGRATION_PLAN.md)
- [Graphics strategy](docs/apple/GRAPHICS_STRATEGY.md)
- [Dependency revisions and provenance](docs/apple/DEPENDENCIES.md)
- [Test matrix](docs/apple/TEST_MATRIX.md)
- [Current game/data/key locations](docs/apple/DATA_LOCATIONS.md)
- [iPhone gameplay](docs/apple/IOS_GAMEPLAY.md)
- [Performance measurements](docs/apple/PHASE7_STATUS.md)
- [Android removal and simple builds](docs/apple/CLEANUP_BUILD_STATUS.md)

## Layout

| Directory | Responsibility |
| --- | --- |
| `engine/host` | Shared guest Win32/runtime, gameplay/native optimizations and preserved renderer helpers |
| `engine/runtime` | Guest CPU/register/memory model and calling conventions |
| `engine/dxvk` | Guest D3D9 COM bridge and retained DXVK overlays |
| `engine/audio`, `engine/io`, `engine/textures` | Portable audio instrumentation, ZIP access and texture tools |
| `engine/uscript` | Preserved original script options/localizations; not required by the Apple build |
| `platform/apple` | Thin macOS/iOS shell, input, presentation, protected storage and platform APIs |
| `tools` | Input verification, static lifting, dependency builds and packaging |
| `tests` | Portable/native regression fixtures; some historical oracles require Windows or device-specific environments |
| `reference` | Third-party source, licenses and original provenance |
| `config` | Pinned original input and dependency manifests |

`generated/`, `build/` and `dist/` are private local outputs. The root Android tree and obsolete APK/JNI launcher recipes have been retired; reusable source and useful fixtures were moved rather than discarded. The local removal report identifies the reference archive and verification.

Use an owned, supported Steam installation. See [LICENSE](LICENSE), [third-party notices](THIRD_PARTY_NOTICES.md), and [BUILDING.md](BUILDING.md) before redistributing any source or compiled derivative.
