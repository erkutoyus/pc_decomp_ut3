# Android removal manifest

Current continuation: the owner explicitly requested removal of the root Android directory and simple macOS/iOS builds. The root tree is now absent; reusable sources and tests were moved into `engine/`, while the original Android implementation is retained in a hash-verified local archive. See [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md) for current verification. The Phase 5 account below records the earlier reference-preserving checkpoint.

Phase 5 removes Android dependencies from the Apple build graph. Shared sources now live in `engine/`. The Android activity, JNI and system backends, driver and texture tooling, APK recipes, and test fixtures remain available. The Android builder selects those sources alongside the same shared engine. The [Phase 5 test matrix](TEST_MATRIX.md) records the M4 checks and the remaining validation limits.

| Android component and responsibility | Apple implementation and dependency removed | Verification and reference disposition |
| --- | --- | --- |
| `android/host/android_main.c`, Android activity, manifest and JNI lifecycle | AppKit owns application activation, window, startup, focus and termination. The shared runtime entry is in `engine/host/main.c`. | Apple closure scan excludes activity, JNI objects and symbols. Desktop launch, folder selection, normal startup, early quit and two gameplay shutdowns were exercised. Android lifecycle sources remain. |
| ANativeWindow leases, surface serials and EGL window hooks | Apple passes retained CAMetalLayer leases and drawable size through its presentation adapter. The D3D9 COM bridge lives in `engine/dxvk` and uses the Apple compile branch. | Native shell resize, device reset, real presents, and teardown passed. The Android lease and EGL paths remain in the reference. External display changes and physical fullscreen switches were outside this run. |
| Android WSI and loader injection | Darwin's DXVK build compiles Metal WSI directly from `platform/apple`. The Apple source preparer no longer reads or stages the Android WSI. Loader and ICD selection use the macOS Vulkan SDK. | Clean Meson graph and Mach-O scan passed. KosmicKrisp presented the validated D3D9 probes and both games. Android WSI bytes still match the prebuilt pin. The MoltenVK binary was audited. Its Phase 3 gameplay limitations remain recorded. |
| Turnip, adrenotools and Android linker namespaces | The Apple build loads the selected Metal-backed ICD from a configured SDK path. Turnip bootstrap and namespace bypass are outside the Apple preprocessor and runtime graph. | No Turnip, adrenotools or namespace shim in compiled dependencies, native imports or bundle contents. Pinned Android driver inputs and packaging are retained. |
| GLES, EGL, MojoShader and Android HLSL compilation | The Apple build uses DXVK Native D3D9 with the existing shared formats, COM ABI, and verified shader bytecode paths. Android's GLES and device shader compiler implementations stay under `android/host`. | D3D9 device, depth/BC formats, SM3, occlusion, 720p and 1080p back-buffer reset and present passed with Vulkan validation. Gameplay rendered through the same path. The Android renderer was preserved in the source selection. |
| Oboe, AAudio, Android OpenAL loader and NDK libc++ | OpenAL Soft is built for CoreAudio with Oboe and OpenSL explicitly off. The shared guest audio shim uses the Mach-O dylib. The portable callback meter uses a byte-identical copy of the pinned reference under `engine/audio`. | Both DirectSound fixtures and real CoreAudio playback passed. No Android audio DSO is embedded or loaded. The Android audio archive, metrics sources, and build recipe are retained. |
| Logcat, Android crash UI and profiling tools | Apple keeps the guest crash journal and stderr/file logging, with AppKit lifecycle events logged through unified logging. Android logcat code remains behind a target guard. | Apple binaries have no logcat import. Headless, early shutdown and gameplay logs recorded orderly exit. The Android crash UI and profiling fixtures remain available. |
| ADPF, Linux affinity, sysfs power and auxv | Apple uses Darwin timing, threads and QoS. IOKit supplies battery and AC facts. Guest processor-power information returns the existing unsupported status on Darwin, whose APIs do not expose the Linux CPUFreq/ACPI contract. | No Android performance or Linux affinity symbols in Apple binaries. An M4 IOKit check reported AC and no battery. VM and synchronization fixtures passed. Android power snapshots, affinity and ADPF code are retained. |
| Launcher paths, assets, save and ZIP handling | The AppKit folder picker selects the original installation. Application Support and the test profile override hold mutable user data. The portable Win32 path and ZIP engine remains shared. | Folder selection, original PE input checks, and real map loading passed. The Android launcher, Java provisioning, and ZIP index writer remain. |
| Android JNI input and credential services | AppKit handles keys, mouse and focus, Game Controller handles the controller snapshot, and Keychain owns protected storage. JNI remains guarded in portable sources where it wraps shared input or post-processing state. | Keyboard, mouse, focus release, XInput snapshot and reuse of the existing protected record passed. A physical controller and online account flow were outside this run. Android touch and credential adapters remain. |
| Android texture converter and cache packaging | The Apple graph retains the portable cache reader and format definitions in `engine`. The Android ASTC/ETC2 converter, Java jobs and codec build remain independent of the Apple build. | Clean graph excludes the converter and Android launcher. BC format and real game rendering passed. Converted Android packs were outside this run. |
| Android UScript options, launcher UI and localizations | AppKit and the existing game front end drive Apple configuration. The Android package build and localization paths remain under `android/uscript` and the APK builder. | Normal offline menus and Instant Action selection worked. The Apple renderer build consumes no Android script package or Java tooling. |
| SDK, NDK, JDK, ADB and APK packaging | CMake, Apple Clang, Ninja and Meson build the Apple app. Shared lifter and DXVK preparation modules are independent of Android tool drivers. The generated COM bridge is local to the Apple build directory. | Fresh Apple outputs built with Android SDK/NDK and Java configuration unset. Compilation databases, Ninja dependencies, native symbols, load commands and bundle contents were scanned. The Android builder still selects the same 80 host translation units in the original order. A Windows-hosted Android APK rebuild was outside this M4 run. |

There are two bundled third-party libraries, DXVK and OpenAL Soft. The Vulkan loader and ICDs are external pinned macOS SDK inputs. The shared engine still uses the authorized original installation and the pinned VC80 image inputs. No Android dependency is required to compile or execute the tested Apple targets.

## Final Phase 5 verification

The M4 clean-build closure and gameplay regression passed on 2026-11-17. The final audit covers 2,090 app/headless/test compilation commands, 143 DXVK commands and 104 OpenAL commands, their Ninja dependencies, native symbols and Mach-O load commands. The runtime self-test, seven CTest fixtures, seven input/generation checks, AppKit checks, validated D3D9 checks, ZIP/save fixture and IOKit snapshot passed.

The normal front end reached Play Offline and Instant Action loaded Deck. Two further 1080p runs reused the same isolated profile. Morbias reached the three-frag scoreboard with Harbinger on three kills and exited through Command-Q with status 0. Deck relaunched, reached the three-frag scoreboard with Evolution on three kills, and exited through native window close with status 0. Both runs produced real CoreAudio samples and recorded input/window teardown with no runtime worker outstanding.

Actual logs and exact commands are indexed in the [Phase 5 test matrix](TEST_MATRIX.md) and [build plan](BUILD_PLAN.md). The remaining teardown HeapFree diagnostics match the saved Phase 4 warning pattern. An initial LaunchServices invocation and the initial input-fixture invocation failed and were followed by the successful native launch and corrected portable fixture runs documented there. Android APK execution, physical controller gameplay and the other untested surfaces remain explicitly listed in the test matrix.

The Android reference is retained. The cleaned Apple target uses the shared source layout and Apple-native dependencies. Phase 6 is pending approval.

## Final directory cleanup — 2026-11-18

| Original source | Preserved shared location |
| --- | --- |
| `android/host/d3d9_ff.c` | `engine/host/d3d9_ff.c` |
| `android/host/d3d9_thread_check.inc` | `engine/host/d3d9_thread_check.inc` |
| `android/host/hlsl_vkd3d.c` | `engine/host/hlsl_vkd3d.c` |
| `android/host/d3d9_resource.c` | `engine/host/d3d9_resource.c` |
| `android/host/d3dx9.c` | `engine/host/d3dx9.c` |
| `android/host/d3d9_thread.c` | `engine/host/d3d9_thread.c` |
| `android/host/d3d9_gl.c` | `engine/host/d3d9_gl.c` |
| `android/host/d3d9_internal.h` | `engine/host/d3d9_internal.h` |
| `android/host/d3d9_format.c` | `engine/host/d3d9_format.c` |
| `android/host/shader_pairs.c` | `engine/host/shader_pairs.c` |
| `android/host/d3d9_shader.c` | `engine/host/d3d9_shader.c` |
| `android/host/d3d9_device.c` | `engine/host/d3d9_device.c` |
| `android/host/d3d9_thread.inc` | `engine/host/d3d9_thread.inc` |
| `android/host/d3d9_texel.c` | `engine/host/d3d9_texel.c` |
| `android/host/guest_mem.c` | `engine/runtime/guest_mem_elf.c` |
| `android/texconv/texconv.h` | `engine/textures/texconv.h` |
| `android/texconv/ue3.h` | `engine/textures/ue3.h` |
| `android/texconv/ut3tex.cpp` | `engine/textures/ut3tex.cpp` |
| `android/texconv/codec.cpp` | `engine/textures/codec.cpp` |
| `android/launcher/native/zipmount.c` | `engine/io/zipmount.c` |
| `android/launcher/native/zipmount.h` | `engine/io/zipmount.h` |
| `android/dxvk/turnip.inc` | `engine/dxvk/legacy_turnip.inc` |
| `android/uscript/.DS_Store` | `engine/uscript/.DS_Store` |
| `android/uscript/AndroidPort/AndroidPortOptions-RUS.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-RUS.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions-ITA.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-ITA.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions-DEU.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-DEU.ini` |
| `android/uscript/AndroidPort/.DS_Store` | `engine/uscript/AndroidPort/.DS_Store` |
| `android/uscript/AndroidPort/AndroidPortOptions-CZE.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-CZE.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions-POL.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-POL.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions-ESN.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-ESN.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions-HUN.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-HUN.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions-FRA.ini` | `engine/uscript/AndroidPort/AndroidPortOptions-FRA.ini` |
| `android/uscript/AndroidPort/AndroidPortOptions.ini` | `engine/uscript/AndroidPort/AndroidPortOptions.ini` |
| `android/uscript/AndroidPort/Classes/AndroidPortValueStore.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortValueStore.uc` |
| `android/uscript/AndroidPort/Classes/AndroidPortDataStore.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortDataStore.uc` |
| `android/uscript/AndroidPort/Classes/AndroidPortMenuScale.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortMenuScale.uc` |
| `android/uscript/AndroidPort/Classes/AndroidPortOptionsPage.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortOptionsPage.uc` |
| `android/uscript/AndroidPort/Classes/AndroidPortCharacterSet.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortCharacterSet.uc` |
| `android/uscript/AndroidPort/Classes/AndroidPortViewportClient.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortViewportClient.uc` |
| `android/uscript/AndroidPort/Classes/AndroidPortSettings.uc` | `engine/uscript/AndroidPort/Classes/AndroidPortSettings.uc` |
| `android/port.json` | `engine/config/legacy_port.json` |

The moves preserve the original implementations. Texture-converter JNI exports are now target-guarded; macOS uses descriptor-owned `flock` instead of Linux OFD locks, with the same exclusion/recovery test passing. Relative includes, test source paths and shared build-helper imports were updated. The ELF-only guest-memory symbol remains separate and is not linked into Mach-O. The legacy Turnip loader remains for retained optional Vulkan fixtures; Apple preprocessing does not include it. The `AndroidPort` script/package identifier is retained for compatibility; it is not an Android SDK/runtime dependency.

The original JNI/ADPF/activity/launcher/WSI files, the retired APK/Android builders and Java-only tests are preserved locally in `build/apple/cleanup/android-reference-before-removal.tar.gz`, SHA-256 `59db0c08c82ba10455a38f674b6189e87a2fcb15c58340af9fd42c193073348c`. The complete per-file hashes, moves and retirement list are in `build/apple/cleanup/migration.json`. Git also retains the original committed reference. Original third-party licenses and dependency provenance remain in the repository.

Retired Android-only tools: `tools/build_android.py`, `tools/build_apk.py`, `tools/build_dxvk.py`, `tools/build_native_audio.py`, `tools/build_turnip.py`, `tools/build_touch_qa.py`, `tools/build_host_test.py`, `tools/profile_cpu.py`, `tools/test_openal.py`, `tools/test_vkd3d.py`. Their imported portable contracts now come from `tools/lift_build.py`. Java/JNI launcher-only tests were archived with their implementations; native query, input, texture, VM, synchronization and gameplay fixtures were retained.

Actual current build/test results and explicit limitations are recorded in [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md).

## Visible data folder update — 2026-11-19

Current macOS/iOS paths, safe legacy migration, remembered Mac installation, build 9 tests and SideStore verification status are in [DATA_LOCATIONS.md](DATA_LOCATIONS.md). Older Documents/Game and Application Support instructions above describe earlier builds.
