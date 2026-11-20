# Dependency and input audit

Record the full source revision, source/archive and binary hashes, overlays, toolchain and architecture in Apple build receipts. The following are the audited pins, with source paths and redistribution terms maintained in [third-party notices](../../THIRD_PARTY_NOTICES.md). The repository license is in [LICENSE](../../LICENSE).

| Dependency | Baseline and location | Apple status |
| --- | --- | --- |
| Steam UT3 | [inputs.json](../../config/inputs.json) pins 41 PE files. [modules.json](../../config/modules.json) has 20 lift specs, including 18 Steam modules and two VC80 modules. | All 41 local Steam files matched by length and hash. The runtime needs its own verified game root. |
| VC80 CRT | 8.0.50727.9680 x86 `msvcr80.dll` and `msvcp80.dll`, both exact hashes in `config/modules.json`. `tools/lift_ut3.py` uses absolute WinSxS paths by default. | Phase 1 extracted both exact files as data from the official Windows 11 LTSC evaluation image. The Steam redistributable contains a different build. `--vc80-root` selects the verified local input directory. |
| Python lifting/tests | `capstone==5.0.7`, `pefile==2024.8.26`, `unicorn==2.1.4`; CPython >=3.12 documented. pcrecomp `904ac3129d0c9d05efbeec19a1dce6abbe7f5d26`, vendored with local adapters. | Phase 1 installed the exact PyPI releases into a CPython 3.13.2 ARM64 venv. Capstone and Unicorn used ARM64 wheels. Unicorn is for host-side tests and analysis. |
| VM and x87 libraries | dlmalloc 2.8.6 (2023 MIT-0 relicensing); x87 window attribution NFSU2 `62a1d3a17fc7619b9d32df182b4b47d1a4f2e959`. [Host pins](../../dependencies-host.json) record copied sources. | Compile the existing source with Apple Clang. No Android runtime binaries required for these components. |
| DXVK Native | 2.4.1, upstream `0cf05780abd7250c2cd713b7749cf32180157cf5`, [source/build pins](../../dependencies-dxvk.json). `reference/dxvk` contains headers/licenses and `reference/dxvk-runtime` contains the patched ELF DSO. Upstream source checkout is absent. | Fetch the exact source when Phase 3 starts. Apply audited overlays and new WSI/loader/Mach-O build rules. Record Meson, Ninja, glslang, header versions and shipped notices. |
| Vulkan to Metal | [Mesa KosmicKrisp](https://docs.mesa3d.org/drivers/kosmickrisp.html) and [Khronos MoltenVK](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md). | Phase 3 candidates. Choose exact Mesa tag/commit and MoltenVK release/commit, loader and Vulkan-Headers after provisioning test builds. Record MoltenVK/SPIRV-Cross revisions and packaging; record Mesa and its toolchain/translator/LLVM dependency closure. No driver pin or compatibility result yet. |
| Shader libraries | MojoShader `cf2661bcb55d9a8732e86f79922592d7efdf5383` with local edits. vkd3d-shader 2.1, parsers generated with Bison 3.8.2 and flex 2.6.4, hash-pinned in [dependencies-vkd3d.json](../../dependencies-vkd3d.json). FSR1 source `a21ffb8f6c13233ba336352bdff293894c706575`. | Preserve shader bytecode paths. Current vkd3d build hard-codes NDK executables. Port the compiler subset build using retained generated parsers. Windows D3DCompiler regenerates checked-in post-FX shaders and can remain an offline oracle. |
| Audio | OpenAL Soft 1.25.2 `b2c48f7718ef3fcf67921a8b6534c4914e328970`; Oboe 1.11.0 `b115f47593969fd67a21e9f63640ffef749b5067`; [audio pins](../../dependencies-audio.json). ELF OpenAL and NDK libc++ are staged in-tree. Pristine upstream source/include tree is absent. | Evaluate pinned OpenAL Soft rebuilt against CoreAudio, retaining guest API and checking source routing, EAX behavior, physical capture/playback and metrics. Use the Apple C++ runtime. iOS adds AVAudioSession routing and interruption integration. |
| Texture and archives | astcenc `baff485b0ff36d2f95d28961605106502c653966`, nested GoogleTest `6910c9d9165801d8827d628cb72eb7ea9dd538c5`, etcpak `3d716e1550023dc5ff8b602636af8b76584e0b66`. [Texture pins](../../dependencies-textures.json). ZIP and other host code use zlib. | Preserve package reader, source-format paths and cache coverage. Treat Android transcode and upload formats as capability-dependent. Apple system SDK zlib is a candidate for the host. |
| Android-only stack | NDK 27.2.12479018, JDK 17+, SDK build-tools 36.0.0 and platform android-37.0 per README. Turnip v26.0.0 R8 (`v26.0.0-rc08`), adrenotools `8fae8ce254dfc1344527e05301e43f37dea2df80`, linkernsbypass `aa3975893d83ef1bc84c321ec60c65fbf1287887`. [Turnip pins](../../dependencies-turnip.json). | Preserve the Android build. Exclude the SDK/NDK, Java, JNI, Oboe, AAudio, Bionic, Android loader components and their ELF DSOs from Apple targets. |
| Other build fixtures | `tools/build_uscript.py` runs the original game compiler on Windows with `subprocess.STARTUPINFO`. The test corpus also contains Windows API and Windows D3D9 oracles. | The Android settings package is outside the CLI self-test. Preserve fixture provenance. Apple menu integration may reuse authorized generated script artifacts or require a separately validated build path. |

Use the original local installation as a read-only input. Keep source/code-generation receipts local when they reference original files, and exclude original binaries, prepared images, rebased PE bytes and assets from distributable packages unless authorized. Track permissions for any compiled derivative and CRT redistribution separately. Prefer a user-supplied CRT path for Apple packaging if embedding rights are unresolved. Retain component notices and applicable LGPL source/relink obligations when distributing a corresponding build.

Phase 1 used the English x64 Windows 11 Enterprise LTSC evaluation ISO `26100.1742.240906-0331.ge_release_svc_refresh_CLIENT_LTSC_EVAL_x64FRE_en-us.iso`, with locally measured SHA-256 `67cec5865eaa037a72ddc633a717a10a2bed50778862267223ddb9c60ef5da68`. PyCdlib 1.14.0 read `/sources/install.wim` from the UDF image. wimlib 1.14.5 extracted the two files from image index 1 at the WinSxS directory pinned in `config/modules.json`. Both output SHA-256 values matched. These readers are separate from the game toolchain. [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise)

## Phase 3 renderer pins

The verified local package was the [LunarG macOS Vulkan SDK 1.4.363.0](https://www.lunarg.com/lunarg-releases-vulkan-sdk-1-4-363-0/). The [SDK ZIP](https://vulkan.lunarg.com/sdk/download/1.4.363.0/mac/vulkansdk-macos-1.4.363.0.zip) had SHA-256 `163431e0203c8215286a17cf393643ce6b951f77d1b4f74ab30821a1f0beb09b`. It supplied the loader, Vulkan validation layer, KosmicKrisp `vulkan-sdk-1.4.363 (git-269a955c89)`, MoltenVK 1.4.2 and glslang 16.6.0. These are prebuilt SDK dependencies. Their internal compiler and translator source revisions need verification before source rebuild or distribution.

DXVK Native 2.4.1 was compiled with the repository's upstream pin and overlays using Apple Clang 21.0.0, Meson 1.9.1 and Ninja 1.13.2. Its checkout included SPIRV-Headers `8b246ff75c6615ba4532fe4fde20f1be090c3764`, Vulkan-Headers `46dc0f6e514f5730784bb2cac2a7c731636839e8`, native DirectX headers `9df86f2341616ef1888ae59919feaa6d4fad693d` and libdisplay-info `275e6459c7ab1ddd4b125f28d0440716e4888078`. The builder checked 954 file pins, accepting equivalent CRLF form for Windows source pins, and emitted `build/apple/dxvk/receipt.json`. The built dylib had SHA-256 `8d530667fafe02c84b23793dc66af2321af00786a83b84019bf8416a3d1b6e1d` and linked to Apple libSystem and libc++.

## Phase 4 CoreAudio pin

The Apple target uses OpenAL Soft 1.25.2 at revision `b2c48f7718ef3fcf67921a8b6534c4914e328970` with the repository-pinned archive SHA-256 `6a3e5f80058ecf994a6885d7db5013629a259c659ab40a6f17db8963ceb211b2`. The build retains NEON and the EAX extensions, requires CoreAudio, and includes the opt-in callback meter from the pinned audio sources. Mach-O dependencies include Apple's AudioToolbox, AudioUnit, and CoreAudio frameworks. The builder writes the library hash and source revision to `build/apple/openal-meter/receipt.json`. [Build commands](BUILD_PLAN.md)

## Phase 5 dependency closure

The Apple graph uses `engine/host`, `engine/runtime`, `engine/dxvk`, the portable texture definitions, and the byte-identical pinned callback meter in `engine/audio`. The Apple tools import `lift_build.py` and `dxvk_source.py` for the existing transformations. The Android recipes remain separate consumers of the shared source.

The clean Phase 5 DXVK build retained upstream `0cf05780abd7250c2cd713b7749cf32180157cf5` and produced dylib SHA-256 `e723cd6c0db2ff1db25d61239340f0389f7bba479cfb196f2dc0dedd120492f2`. The CoreAudio OpenAL build retained revision `b2c48f7718ef3fcf67921a8b6534c4914e328970` and produced dylib SHA-256 `40cb8f5e32f31636d4d2d11c584693038e9c16b630346afddb6b6a9aed950c9d`. Receipts are in `build/apple/phase5/{dxvk,openal}/receipt.json`.

The compile graph and recorded Ninja include dependencies contain no Android source, SDK or NDK inputs. Mach-O load commands and native symbols were audited for the app, headless runtime, both bundled dylibs, and external SDK loader and ICDs. The app embeds DXVK and OpenAL. Its Vulkan SDK remains a configured external development dependency. Android's pinned WSI and four prebuilt overlay hashes still match, and the Android host source selection retains all 80 original translation units. A full Android APK build requires its reference Windows toolchain and was outside the M4 verification.


## Phase 6 iOS slices (2026-11-17)

DXVK Native retains revision `0cf05780abd7250c2cd713b7749cf32180157cf5` and the existing pinned overlays. The clean iphoneos ARM64 cross-build produced SHA-256 `17aef26e8328e011349107427f674271214470394adcff13eb06603d79339f79`, receipt `build/apple/phase6/dxvk/receipt.json`. It uses Apple Clang 21.0.0, iPhoneOS27.2 SDK, Meson1.9.1 and host glslang from the existing pinned SDK. No Vulkan feature requirement was reduced.

MoltenVK1.4.2 comes from that same pinned SDK archive, specifically `MoltenVK.xcframework/ios-arm64/libMoltenVK.a`, SHA-256 `c5c75b112ba4102d17b353f223d2d8e36438c962a3f9cb615423962ae213f288`. This is a prebuilt iOS static slice, not the macOS binary. Exact internal translator source revisions remain the pre-existing SDK source-rebuild/distribution follow-up. The app links UIKit/Foundation/Metal/QuartzCore/IOSurface/CoreGraphics and common system frameworks; AppKit and IOKit are excluded on iOS. Signing material remains private, provisioned by Xcode. No iOS OpenAL binary or working audio session is claimed.


## Phase 6 D3D9 compatibility overlay

No dependency revision upgrade. `tools/d3d9_portability.py` adds an iOS-only exact-context overlay to the existing pinned native DXVK sources. The separate build `build/apple/phase6/dxvk-portability` records source-overlay hashes and its resulting unsigned dylib hash in `receipt.json`. The original Phase 6 DXVK directory preserves the initial device-creation failure baseline. MoltenVK remains the same pinned iOS static slice. [Behavior, tests and allocation tradeoff](D3D9_PORTABILITY.md).

The reproduced build with the dedicated optimal-image allocation correction has unsigned dylib SHA-256 `3db56c4bcb1598bc403ba20f511bdbf13f57ac03fb004021cc6dbb1ccd6928f1`. It matches the unsigned app staging copy. Overlay hashes are in its receipt. After device unlock, the reproduced build passed the D3D9 ARGB/dynamic-sampler fixture and two real UT3 first-frame/exit runs with Metal API and GPU shader validation enabled. Full gameplay and memory-pressure validation remain pending.


## Phase 6 gameplay continuation (2026-11-18)

The native UIKit keyboard, GameController/XInput bridge and pinned OpenAL Soft RemoteIO backend are implemented. The owner verified keyboard typing/deletion/Done, clear sound and a full offline match with GameSir X5 Lite. The owner also verified correct touch selection, keyboard operation, one-second Keyboard button disappearance, and audible sound/controller recovery after restoring the app. Explicit foreground audio-session/device recovery is implemented; external route changes, interruptions and memory pressure remain unverified. Earlier pending statements above describe previous checkpoints. [Current evidence, exact commands, source boundaries and unresolved issues](IOS_GAMEPLAY.md). Phase 7 has not started.

## Phase 7 iPhone performance update

See [PHASE7_STATUS.md](PHASE7_STATUS.md) for the 720p/60 FPS target, exact commands, pinned dependency continuity, measured results, optional experiments and remaining failures.

## Simple builds and final directory cleanup

The owner-authorized root Android removal and two-command Apple build path are documented in [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md). Use [BUILDING.md](../../BUILDING.md) for current beginner instructions; older Android-reference/build statements above describe earlier checkpoints.
