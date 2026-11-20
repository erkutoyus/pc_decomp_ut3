# Apple test matrix

## Phase 2 results on the Mac mini M4

| Check | Actual result |
| --- | --- |
| Bundle | CMake/Ninja built `Unreal Tournament 3.app`. `plutil -lint` accepted its Info.plist. `file` reported an ARM64 Mach-O and `otool -L` showed Apple frameworks, system libraries and zlib. |
| Startup and window | Direct and LaunchServices runs showed a visible key window with a 960×540 backing surface. Each passed the existing runtime self-test on the startup worker. Native resize updated the view-owned CAMetalLayer and the guest dimensions. |
| Input | In-process AppKit events passed W down/up, DirectInput keyboard snapshot, left/right Shift overlap, cursor coordinates, relative mouse motion, button and wheel checks. Hiding the key window released active input. Synthetic controller snapshots passed XInput slot, packet, button, trigger, axis and disconnect checks. Physical controller hardware and haptics were outside this validation. |
| Shutdown and ownership | Automatic close after validation and Quit during startup both exited cleanly. Early Quit deferred until the runtime worker completed. All runs recorded a detached window/view, released input and no outstanding startup worker. |
| Startup error | An incomplete workspace-only game directory produced engine status 67, a diagnostic journal and clean shell teardown. The validation marker correctly reported failure. The AppKit process itself used normal application termination. |
| Regression | 3/3 native runtime CTest fixtures passed. The separate headless CLI self-test also passed after the shared runtime changes. GUI validation used explicit workspace data directories and synthetic input. The default Application Support path and interactive folder picker were not exercised in those runs. |

The restricted process environment reported zero AppKit screens. The graphical login session reported one, and all the window tests ran there. Positive validation runs reported `PHASE 2 VALIDATION PASS` in `shell.log` and the original runtime PASS marker in `ut3.log`.

```sh
cmake --build build/apple/macos --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
ut3_bundle="$PWD/build/apple/macos/Unreal Tournament 3.app"
ut3_binary="$ut3_bundle/Contents/MacOS/Unreal Tournament 3"
plutil -lint "$ut3_bundle/Contents/Info.plist"
file "$ut3_binary"
otool -L "$ut3_binary"

ut3_window_data=$(mktemp -d "$PWD/build/apple/phase2-window.XXXXXX")
"$ut3_binary" --game "$PWD/../UT3" --data "$ut3_window_data" --validate-shell >"$ut3_window_data/console.log" 2>&1
rg -F 'PHASE 2 VALIDATION PASS' "$ut3_window_data/shell.log"

ut3_quit_data=$(mktemp -d "$PWD/build/apple/phase2-quit.XXXXXX")
"$ut3_binary" --game "$PWD/../UT3" --data "$ut3_quit_data" --validate-early-quit >"$ut3_quit_data/console.log" 2>&1
rg -F 'PHASE 2 VALIDATION PASS' "$ut3_quit_data/shell.log"

ut3_launch_data=$(mktemp -d "$PWD/build/apple/phase2-launch.XXXXXX")
open -n -W "$ut3_bundle" --args --game "$PWD/../UT3" --data "$ut3_launch_data" --validate-shell
rg -F 'PHASE 2 VALIDATION PASS' "$ut3_launch_data/shell.log"
```

The recorded run directories are named in `build/apple/phase2-{shell,early-quit,bootstrap-error,launchservices}-path.txt`. They contain `shell.log`, `ut3.log`, `ut3-crash.txt` and `exit-status.txt`. The direct runs also captured AppKit stderr and engine output together in `console.log`. The CTest output is in `build/apple/phase2-ctest.log`.

## Phase 1 results on the Mac mini M4

| Check | Actual result |
| --- | --- |
| Inputs and generation | All 41 Steam pins and both VC80 pins verified. The lifter generated 20 PE modules, 2,006 C translation units including dispatch, and 199,342 lifted entries. The native PE fixture compared all 20 prepared images byte for byte and rejected damaged, missing and unknown files. |
| Native executable | `ut3-runtime-selftest` is an ARM64 Mach-O. Its linked libraries are macOS `libz.1.dylib` and `libSystem.B.dylib`. Both `UT3_EXECUTION_MODE=optimal` and `exact` returned exit 0 using separate new data directories. |
| Built-in startup | It reserved `0x7000000000..0x7100000000` with 16 KiB host pages, initialized the dispatch and PE modules, executed lifted DLL attach and reached `[selftest] PE binding, DLL/TLS startup, guest heap and static entry lookup PASS; game entry not executed`. |
| Guest VM, ABI and threads | CTest passed 3/3. `virtual-alloc` covered guest subpage zero-on-recommit, adjacent committed data, file mapping, write-through and release. `named-events` and `critical-sections` covered guest stdcall, handles and events, recursive entry and native pthread contention. |
| Native overrides and diagnostics | Standalone Apple Clang fixtures passed Mach-O direct, same-unit and indirect calls, original-body entry, C EH metadata vectors, and the native signal journal. |
| Python regression suites | 31 tests passed across the measured frame tools, PE image fixture, EH recovery and metadata checks, trap audits, coverage, and x87 slot pass. The separate original-x86 VC80 oracle using Unicorn 2.1.4 exited with SIGILL. The native CLI has no Unicorn dependency. |
| Timing | The two warm startup runs took 0.110 s (`optimal`) and 0.107 s (`exact`). Python reported a cumulative child peak RSS of 104.5 MiB. These are startup observations. |

The headless run reported 59 modules, including Win32 pseudo-modules, and 528 host import gaps. The headless target leaves renderer, device audio and networking outside its source list. The gaps remain an inventory for the application and gameplay phases. The initial build hits were a fixture function named `wait` and unresolved platform hooks in Mach-O. The final build and native fixtures passed after those were corrected. The first instrumented run logged process exit 0, but Darwin's `/usr/bin/time -l` wrapper returned 1 after a sandbox `sysctl` failure. The two exit 0 results above come from direct subprocess execution.

### Commands used

```sh
/opt/homebrew/bin/python3.13 -m venv build/apple/venv
build/apple/venv/bin/python -m pip --no-cache-dir --index-url https://pypi.org/simple -r requirements.txt
build/apple/venv/bin/python -B tools/inspect_inputs.py --root ../UT3 --verify
build/apple/venv/bin/python -uB tools/lift_ut3.py --game-root ../UT3 --module ut3
build/apple/venv/bin/python -uB tools/lift_ut3.py --game-root ../UT3 \
  --module wxmsw262u --module wxdockitu --module fxgraphlayout --module libresample \
  --module ogg --module vorbis --module vorbisenc --module vorbisfile --module binkw32 \
  --module nxcooking --module nxcharacter --module physxloader --module physxcore \
  --module steam_api --module steamclient --module tier0_s --module vstdlib_s
build/apple/venv/bin/python -uB tools/lift_ut3.py --game-root ../UT3 \
  --vc80-root build/apple/vc80 --module msvcr80 --module msvcp80
cmake -S . -B build/apple/macos -G Ninja -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_BUILD_TYPE=Release -DPython3_EXECUTABLE="$PWD/build/apple/venv/bin/python"
cmake --build build/apple/macos --parallel 8
file build/apple/macos/ut3-runtime-selftest
otool -L build/apple/macos/ut3-runtime-selftest
ctest --test-dir build/apple/macos --output-on-failure -V
```

```sh
export TMPDIR=/private/tmp UT3_TEST_GAME_ROOT="$PWD/../UT3" UT3_TEST_VC80_ROOT="$PWD/build/apple/vc80"
build/apple/venv/bin/python -uB -m unittest tests.test_measure_frames
build/apple/venv/bin/python -uB -m unittest tests.test_pe_images \
  tests.test_eh_metadata.MetadataTest.test_real_wrapper_and_rejected_mutations \
  tests.test_eh_prolog3.Prolog3Test.test_real_catch_owner_adds_cold_continuation \
  tests.test_eh_prolog3.Prolog3Test.test_reject_changed_helper_and_seh4 \
  tests.test_audit_traps tests.test_function_coverage tests.test_x87_slots
```

The runtime invocation is in the [build plan](BUILD_PLAN.md). Captured logs are under the local, untracked `build/apple/` directory. `selftest-optimal-path.txt` and `selftest-exact-path.txt` identify directories containing `console.log`, `ut3.log`, `exit-status.txt` and `timing.txt`. The remaining logs are `ctest.log`, `regression-tests.log`, `measurement-tests.log`, `wrap-fixture.log`, `crash-journal-test.log`, `eh-probe.log` and `unicorn-oracle.log`.

## Phase 0 results on the Mac mini M4

| Check | Command or method | Actual result |
| --- | --- | --- |
| Baseline | `git status --short --branch`, `git rev-parse HEAD`, `git submodule status --recursive` | Clean initial `main`, `f8d1323e4b44c124eba8ecc08364debd32c021a7`. Texture submodules and nested GoogleTest are present at the pins. |
| Toolchain/host | `uname -m`, `sw_vers`, `system_profiler SPHardwareDataType`, `xcodebuild -version`, `xcodebuild -showsdks`, `xcrun --sdk macosx --show-sdk-path`, `xcrun --sdk iphoneos --show-sdk-path`, `clang --version`, `cmake --version`, `ninja --version`, `getconf PAGESIZE` | Native ARM64 and 16 KiB pages. Versions in [build plan](BUILD_PLAN.md). Xcode emitted sandbox/cache and FSEvents warnings and returned SDK results. |
| Steam pins | `python3 -B tools/inspect_inputs.py --root ../UT3 --verify`; independent stdlib check below | Repository CLI exits with missing `pefile`. Independent check matched 41/41 pinned lengths and hashes. Asset completeness and gameplay are pending. |
| VC80 redistributable | Read-only nested CAB inspection described below | Steam redist contains both named DLLs. Neither matches its pinned SHA-256. Exact CRT inputs remain outstanding. |
| Python requirements | `/opt/homebrew/bin/python3.13 -m venv "$ut3_audit_tmp/venv"` then `"$ut3_audit_tmp/venv/bin/python" -m pip --disable-pip-version-check --timeout 5 --retries 0 install -r requirements.txt` | Venv creation succeeded. Pip found no matching `capstone==5.0.7` through the available package index in this environment. No conclusion about availability on a trusted external index or wheelhouse. |
| Pure Python regression subset | `TMPDIR=/private/tmp python3 -B -m unittest tests.test_audit_traps tests.test_function_coverage tests.test_measure_frames tests.test_x87_slots` | 26 passed. With default TMPDIR, `test_function_coverage` produced six `Path.relative_to` errors from `/private/var` versus `/var`. `tests.test_profile_guard` could not import `pefile`. |
| Windows GPU test drivers | `python3 -B -m unittest tests.test_dxvk_query_pools tests.test_dxvk_pipeline_cache_prune` or load each module separately | Audited both modules in separate combined-suite attempts. Each aborts during test loading through `tests.host_environment` with `KeyError: LOCALAPPDATA`. This harness resolves a Windows NDK Clang toolchain. |
| Mach-O assembly/override | Clang commands below | `guest_mem.c` fails at ELF `.hidden`; Apple linker rejects `--wrap`. Clang accepted `-mllvm -basic-aa-separate-storage` for the standalone probe. The optimization's production lowering remains unverified. |
| Native VM probe | Standalone C11 test, built as an ARM64 Mach-O with Apple Clang | Exact-address `mmap` check failed at existing base and returned `0x7000000000`. A fixed, non-overwrite Mach allocation at `0x2000000000` reported 3 (`KERN_NO_SPACE`). At `0x7000000000` the hint and Mach fixed allocation succeeded in three runs, a duplicate fixed allocation was rejected, and whole-page owned replacement yielded zero where `MADV_DONTNEED` retained `0xa5`. The probe did not use the UT3 host. |
| Full lift, link, runtime, graphics and performance | Phase 1+ | Pending. No macOS UT3 executable, device run, renderer measurement, or performance baseline in Phase 0. |

### Read-only Steam and CRT checks

```sh
python3 -B - <<'PY'
import hashlib, json
from pathlib import Path

root = Path('../UT3')
rows = json.loads(Path('config/inputs.json').read_text())['modules']
bad = []
for row in rows:
    path = root / row['path']
    if not path.is_file() or path.stat().st_size != row['size']:
        bad.append(row['path'])
        continue
    with path.open('rb') as binary:
        if hashlib.file_digest(binary, 'sha256').hexdigest() != row['sha256']:
            bad.append(row['path'])
print(f'{len(rows) - len(bad)}/{len(rows)} Steam input pins matched. Missing or changed: {bad}')
raise SystemExit(bool(bad))
PY
```

For this specific installer, locate CABs by the `MSCF` signature and the little-endian CAB size at header offset 8. The outer CAB starts at `0xfd54` in `../UT3/VCRedist/vcredist.exe`. Use `tar -xOf` to stream `VCREDI~1.EXE` and repeat at offset `0xfd54` in that file to get `vcredist.msi`. The CRT CAB begins at offset `0x1c4800` in the MSI. List it with `tar -tf`, then hash each DLL with `tar -xOf payload.cab "$entry" | shasum -a 256` (using the extracted CRT CAB as `payload.cab`). The standard, `ul_` and `nosxs_` variants have the same hashes per DLL.

| Steam redist member | SHA-256 | Match |
| --- | --- | --- |
| `msvcr80.dll.98CB24AD_52FB_DB5F_FF1F_C8B3B9A1E18E` | `120cd25f5d6002ffd9069cf9550bc16c682bcd3323053b95146e7cd3ba2215ac` | No |
| `msvcp80.dll.98CB24AD_52FB_DB5F_FF1F_C8B3B9A1E18E` | `9fc2e85ba84cf0459aab0dc2efac734ad7b5b4c99ba19871fe8f6e35d0191838` | No |

### VM probe reproduction

Place the following in a temporary `vm.c`. The initial Phase 0 probe stopped on a non-matching hint. This form also checks exact Mach allocation and zero-fill and can be compiled for both candidate bases.

```c
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void)
{
    const size_t span = 0x100000000ull;
    const long page = sysconf(_SC_PAGESIZE);
    void *want = (void *)(uintptr_t)UT3_VM_PROBE_BASE;
    void *hint = mmap(want, span, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (hint == MAP_FAILED) { perror("mmap"); return 1; }
    printf("page=%ld mapping=%p exact=%d\n", page, hint, hint == want);
    if (munmap(hint, span)) { perror("munmap"); return 2; }

    mach_vm_address_t addr = (mach_vm_address_t)(uintptr_t)want;
    kern_return_t status = mach_vm_allocate(mach_task_self(), &addr, span, VM_FLAGS_FIXED);
    printf("mach_vm_allocate fixed status=%d address=0x%llx\n", status, addr);
    if (status != KERN_SUCCESS) return 8;
    mach_vm_address_t duplicate = addr;
    status = mach_vm_allocate(mach_task_self(), &duplicate, (mach_vm_size_t)page, VM_FLAGS_FIXED);
    printf("overlapping fixed request status=%d\n", status);
    if (status == KERN_SUCCESS) return 9;

    void *got = (void *)(uintptr_t)addr;
    if (mprotect(got, span, PROT_NONE)) { perror("protect reserve"); return 10; }
    volatile uint8_t *sample = (uint8_t *)got + 0x400000;
    if (mprotect((void *)sample, (size_t)page, PROT_READ | PROT_WRITE)) return 3;
    *sample = 0xa5;
    if (madvise((void *)sample, (size_t)page, MADV_DONTNEED)) return 4;
    if (mprotect((void *)sample, (size_t)page, PROT_NONE) ||
        mprotect((void *)sample, (size_t)page, PROT_READ | PROT_WRITE)) return 5;
    printf("byte after MADV_DONTNEED and protect cycle=0x%02x\n", *sample);

    got = mmap((void *)sample, (size_t)page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (got != (void *)sample) return 6;
    if (mprotect(got, (size_t)page, PROT_READ | PROT_WRITE)) return 7;
    printf("byte after owned-page replacement=0x%02x\n", *sample);
    return munmap(want, span) != 0;
}
```

```sh
xcrun --sdk macosx clang -arch arm64 -std=c11 -Wall -Wextra -DUT3_VM_PROBE_BASE=0x2000000000ull /tmp/ut3-vm/vm.c -o /tmp/ut3-vm/original
file /tmp/ut3-vm/original
/tmp/ut3-vm/original
xcrun --sdk macosx clang -arch arm64 -std=c11 -Wall -Wextra -DUT3_VM_PROBE_BASE=0x7000000000ull /tmp/ut3-vm/vm.c -o /tmp/ut3-vm/candidate
/tmp/ut3-vm/candidate && /tmp/ut3-vm/candidate && /tmp/ut3-vm/candidate
xcrun --sdk macosx clang -arch arm64 -c android/host/guest_mem.c -o /tmp/ut3-vm/guest_mem.o
xcrun --sdk macosx clang -arch arm64 -DUT3_VM_PROBE_BASE=0x2000000000ull /tmp/ut3-vm/vm.c -Wl,--wrap=sub_00400000 -o /tmp/ut3-vm/wrap
xcrun --sdk macosx clang -arch arm64 -DUT3_VM_PROBE_BASE=0x2000000000ull -c -mllvm -basic-aa-separate-storage /tmp/ut3-vm/vm.c -o /tmp/ut3-vm/aa.o
```

## Regression coverage to carry forward

| Gate | Existing fixtures to reuse | Apple acceptance |
| --- | --- | --- |
| Phase 1 inputs and translation | `test_inspect_inputs.py`, `test_lift_inputs.py`, `test_pe_images.py`, `test_call_next.py`, `test_audit_traps.py`, x87/xmm and local-reg tests | All required inputs and reports match. Run host-side generator tests with real inputs. Test Mach-O original/override calls and exact/optimized equivalence. |
| Phase 1 guest VM and PE | `test_virtual_alloc.c` and its Windows oracle, `test_pe_images.c`, `test_pe_imports.c`, `test_pe_resources.c`, `test_eh_metadata.py`, `test_eh_prolog3.py` | Run original self-test, verify imports/TLS/attach; test mapped views, recommit, host crash and guest EH behavior separately. |
| Phase 1 thread and ABI | `test_critical_sections.c`, `test_named_events.c`, `test_queued_thread.c`, `test_native_affinity.c`, `test_contract_native.c`, `test_site_cache.c`, `test_xmm_separate.c` | Prove thread handoff, register/calling semantics, TLS ownership, event timing and safe synchronization. Keep Windows/Android oracles for comparison. |
| Phase 2 window and input | `test_message_queue.c`, `test_xinput.c`, `test_dinput_overflow.c`, `test_window_owner.c`, `test_touch_release.c` | Validate main-thread lifecycle; focus-loss releases, quit, mouse/cursor, input queue, controller/reconnect and user-data separation. |
| Phase 3 rendering | `test_dxvk_bridge.cpp`, `test_dxvk_bc_caps.cpp`, GPU query/occlusion tests, `test_dxvk_scaled_spirv.py`, shader-cache and render resource fixtures, existing D3D9 lifecycle self-test | Native clear to CAMetalLayer before UT3, then COM lifetimes, shader and format correctness, and captured UT3 frame on each viable backend. |
| Phase 4–5 gameplay and cleanup | `test_openal.c`, DirectSound fixtures, `test_physx_box.c`, `test_physx_effects.c`, `test_zip_saves.c`, native AI/render differential cases and frame measurement tools | Real playback, repeat startup/menu/map/gameplay/shutdown. Compare native and exact modes and ensure Android build dependency closure is absent from the Apple target. |
| Early iOS feasibility and Phase 6–7 | Darwin VM checks and shared runtime/renderer fixtures, portable touch fixtures where applicable | Signed physical-device feasibility before UI port, then device gameplay and background/foreground tests. Capture sustained performance and thermal/power behavior. |

`tools/build_host_test.py` links fixtures against production Android objects with a Windows NDK Clang and ELF linker flags. Several wrappers run through ADB using `UT3_TEST_ANDROID`, require generated source, execute Java, or call Win32 directly. Port the reusable fixture bodies to the Apple target and keep Windows/Android oracles available for comparisons. Report environmental failures and skips alongside production results.

## Phase 3 M4 results

macOS 27.2 (26B123), Apple M4, native ARM64 AppKit application and DXVK dylib. Commands and exact dependency selections are in [the build plan](BUILD_PLAN.md) and [dependency pins](DEPENDENCIES.md). Local captures and raw output are under `build/apple/phase3-captures`.

| Test | Result and evidence |
| --- | --- |
| KosmicKrisp standalone Vulkan WSI | Pass, exact 640×400 RGB (37, 160, 123) readback, FIFO present accepted, no validation errors. `libkosmickrisp-wsi.log` and `libkosmickrisp-clear.ppm`. |
| MoltenVK standalone Vulkan WSI | Pass, same readback and present, no validation errors. `MoltenVK-wsi.log` and `MoltenVK-clear.ppm`. Standalone validation ran before connecting DXVK. |
| KosmicKrisp guest D3D9 probe | Pass, fixture created the guest COM device and a D24S8-compatible depth surface, checked BGRA8, RGBA16F, BC1 and BC3, wrote through a managed texture lock, drew with SM3, queried 56,310 occlusion samples and submitted a Vulkan present. Zero Vulkan validation errors. `kosmickrisp-d3d9-final/console.log`. |
| MoltenVK guest D3D9 probe | Failed at CreateDevice with HRESULT `8876086a`. Validation reports `robustBufferAccess2` and `nullDescriptor` unavailable. `MoltenVK-d3d9-final/console.log`. |
| UT3 with validation enabled | The initial capture run produced a frame after roughly 24 seconds with `06479` validation errors. The corrected run captured the 640×480 startup frame 7.608 seconds after launch and logged accepted Vulkan presentation. It had zero validation errors and ten unused fragment output warnings. Its first five-second sample reported 62.2 queue presents/s. `game-shadow-validation/{console.log,control.log,ut3-first-frame.ppm,ut3-first-frame.png}`. |
| UT3 repeat with validation layer disabled | Fresh data directory. First non-uniform back-buffer capture at 5.783 seconds with Vulkan presentation accepted. First five-second sample reported 62.4 queue presents/s. These are startup observations on the front end. `game-final-no-layer/{console.log,control.log,ut3-first-frame.ppm}`. Both runs ended with test-harness SIGTERM eight seconds after capture. |
| Regression suite | Seven native CTest fixtures passed: VM, named events, critical sections, WSA events, TCP/UDP loopback readiness, DirectSound capture and endpoint enumeration. `ctest-final-retry.log`. The initial loopback fixture expected an immediate refusal from a bound, non-listening port. A native socket probe showed that Darwin keeps that connection pending, and the Darwin fixture releases the port before testing refusal. |
| AppKit input and quit | A direct run in a sequence of apps failed the key-window assertion. Launch Services retry passed the full keyboard, mouse, focus release, drawable sizing, controller snapshot and shell teardown fixture. Early Quit separately passed. `shell-final-retry/shell.log` and `shell-early-quit-final/console.log`. |
| Legacy DXVK Python suite | Six collection/setup errors on macOS from Windows/NDK paths, a missing ELF test dependency and an absent generated before/after fixture. `python-dxvk.log`. The native WSI and real COM probe supply the hardware results in this table. |

Remaining graphics work includes runtime HLSL compilation, validating game content and cursor/layout at other resolutions, depth-only validation warnings, unsupported wireframe and ProcessVertices on this ICD, and sustained performance and resource lifetime under gameplay. The physical audio backend and normal interactive guest shutdown have not been exercised. The next phase starts only after approval.

## Phase 4 offline play on the M4

Native ARM64 AppKit front end, pinned DXVK and KosmicKrisp, OpenAL Soft with CoreAudio, 960×540. The player used the locally owned Steam installation and supplied the original key in the game. Commands are in [the build plan](BUILD_PLAN.md). Captures and logs are under `build/apple/phase4-captures` and `build/apple/phase4-playtest`.

| Test | Result |
| --- | --- |
| Interactive startup and saved configuration | The game accepted the player's CD key and saved a Keychain record. A rebuilt app waited in SecItemCopyMatching until Keychain access was granted. It then skipped the CD Key screen, reached the normal login page, and entered the main menu as Player (Offline). |
| Menu input | Escape navigated back from Settings. Arrow keys and Return selected Instant Action, Deathmatch, and Deck. Text editing changed the time limit and toggled Force Respawn. The automated click on Start Game did not consistently trigger that button, so Deck travel used the game's F10 console and the `open dm-deck` command. |
| Map load and player control | Deck loaded in 1.168 seconds according to UE3. Primary fire started the match. Keyboard movement changed the player's location, primary fire reduced ammo from 50 to 48, and bots dealt damage. The game wrote its own screenshot, exported as `deck-match.png`. |
| Completed offline match | A second sound-enabled run loaded DM-Morbias in 1.040 seconds through UT3's map URL. Movement and shots registered. Barktooth won with three kills in the post-match scoreboard. `morbias-match.png` is the in-game capture during play. |
| Native audio | Real 44.1 kHz stereo CoreAudio output. The timed match logged 6,086 callbacks and more than 4.5 million nonzero samples, zero nonfinite samples, and zero guest OpenAL errors in the measured interval. Device selection used the game's Generic Software setting. The test observed audio buffers at the CoreAudio callback and did not use a physical microphone. |
| Repeated startup and shutdown | The interactive Deck run exited through Command-Q. The Morbias repeat exited through Close Window. Both recorded UE3's `appRequestExit(0)`, engine and audio device shutdown, AppKit detachment, and process exit 0. The earlier WM_CLOSE-only prototype stalled and was terminated after its run. |
| Shared regression | Native headless startup and all seven CTest fixtures passed after the Phase 4 build. |
| Performance | Morbias usually logged about 61–62 Vulkan queue presents per second during the short match. More complex Deck samples fell to 21.6–50.7 with up to about 1,900 draws per frame and 27.7 ms spent in the native Present call in the slowest sampled Deck interval. These short playtests do not establish a sustained frame-rate target. |

The test path used `-nomovie`. Bink playback, DirectSound hardware output, gamepad match play, and online voice remain open. The engine logged VoiceInterface warnings during bot portraits. Retain the Android build and source while Phase 5 verifies the Apple dependency closure.

### Phase 4 video and performance follow-up

| Check | M4 result |
| --- | --- |
| D3D9 mode enumeration and reset | The guest COM probe enumerated 720p and 1080p, reset to each mode, verified the actual back-buffer dimensions, and presented. The draw, SM3 shader and occlusion checks passed. The run produced no Vulkan VUID messages on KosmicKrisp. |
| UT3 Video menu and persistence | An offline Morbias launch without a resolution flag started at the stock 1280×1024. Mouse selection worked through the letterbox. The Video menu offered 720p, 900p, 1080p and 1440p. Applied and accepted 1920×1080, quit with status 0, and relaunched the same profile. UE3 requested a 1920×1080 back buffer again and presented the match. |
| Warm pipeline-cache read | For the same local 57,025,296-byte cache, the previous iterator read took a median 130.28 ms across nine measured runs and the new bulk read took 11.94 ms. The measurements cover file reading and vector construction with a warm filesystem cache. DXVK's Vulkan cache-header checks still apply. |
| Gameplay stalls | The 1080p Morbias relaunch reached approximately 62 accepted presents per second after warm-up. Early gaps of 170–221 ms persisted, several alongside streaming reads. A 960×540 Deck baseline also showed early 147–230 ms gaps and occasional later gaps with no logged file I/O. Logged file time explains only part of these stalls. |
| Immediate vs. FIFO presentation | Two 21-second 1080p Morbias runs per mode, with a stationary camera, the same initial Vulkan cache and the guest's stock limiter. The largest gaps in the first five seconds were 302 and 245 ms for immediate, and 233 and 241 ms for FIFO. Each mode reached about 62 accepted presents per second after warm-up, with no gaps above 25 ms in the subsequent three reporting intervals. This test did not establish a steady-state benefit from overriding the game's presentation interval. |

Local evidence is in `build/apple/phase4-perf` under `baseline`, `modes-final`, `game-modes` and `pacing-*`, and in `cache-bench.log`. The pacing harness varies `DXVK_CONFIG` between `d3d9.presentInterval = 0` and `d3d9.presentInterval = 1`. The cache benchmark measures file reading only.

### Phase 4 stutter investigation on the M4

The app ran the pinned KosmicKrisp backend at a 1920×1080 D3D9 back buffer in the normal 960×540 backing-pixel window. The local Deck URL starts an offline deathmatch in spectator view with `NumPlay=8`, `QuickStart=1` and the stock frame limiter. Per-frame CSVs measure the interval between unique accepted Vulkan presents. They measure submission cadence.

- Instruments Time Profiler stacks were aligned to the long-frame signposts. In five early 175–250 ms gaps, 74–107 of the game thread's sampled stacks were inside VC80 `_vsnwprintf_s`. The same gaps included 20–37 ms of timed file reads and 4–8 MiB of streaming each. The native ARM64 path now handles verified unpadded UTF-16 formats and bounded count truncation. Complex formats and invalid-parameter behavior still use the pinned VC80 routine.
- Match traces contained 149–200 ms gaps with synchronous KosmicKrisp pipeline creation in the DXVK command stream, including `vkCreateGraphicsPipelines` on a draw. An isolated 1,014 ms baseline gap had only eight running samples on the game thread, so this capture did not establish the wait responsible for it. Separate two- and four-worker DXVK trials produced mixed frame times, so the default compiler worker count stayed in place.
- The extended implementation matched the live VC80 return value and destination bytes on more than 220,000 calls in a Deck verification run. The local ARM64 fixture also checked UTF-16 across a guest page boundary, signed and unsigned values, padded fallback, and both truncation forms, including the guest CRT `errno`. The fixture, native runtime self-test, and seven CTest tests passed.

The final untraced A/B used macOS 27.2 and two runs per configuration in original, native, native, original order. Each run started with a fresh profile and identical copies of the Vulkan pipeline and DXVK state caches. The guest seed was fixed but bot actions and draw counts varied across runs. The initial window is the first five seconds after the first accepted present. The match window is seconds 5–20.

| Metric | Original VC80 | Native fast path |
| --- | ---: | ---: |
| Median process launch to first accepted present | 6.75 s | 6.57 s |
| Median initial p95 frame gap | 27.5 ms | 27.4 ms |
| Median initial p99 frame gap | 176.1 ms | 175.2 ms |
| Largest initial gap across both runs | 243.0 ms | 215.5 ms |
| Initial gaps above 100 ms across both runs | 10 | 10 |
| Median match p99 frame gap | 19.4 ms | 19.3 ms |
| Largest match gap across both runs | 32.9 ms | 25.8 ms |

The small launch and worst-gap improvements are observed across these runs. The percentile results show little change, and game-thread scheduling and first-use graphics compilation still require investigation.

Commands for the build and profiling are in [the build plan](BUILD_PLAN.md). Local evidence is in `build/apple/phase4-stutter`, including `deck-marked.trace`, `deck-format.trace`, `deck-system.trace`, `crt-final-ab.log` and the per-run `frames.csv` files.

### Manual launch and pointer follow-up

The macOS fault report showed the earlier Finder crash in DXVK's loader function table when the Vulkan loader was absent. The rebuilt app was opened through Launch Services with no graphics environment overrides, and the folder picker accepted the original UT3 directory. UT3 reached its real CD Key screen with the D3D9 and audio devices initialized in a fresh data directory, then exited through Command-Q. The missing-loader test reported a startup error before guest execution. The AppKit fixture verified both vertical client positions and the direction of a relative movement event, and real menu clicks aligned at different screen heights. Physical mouse feel still needs confirmation from the player who reported the original inversion.

## Phase 5 M4 cleanup regression

Verified on macOS 27.2, Apple M4, on branch `codex/apple-phase5`. The clean native app is `build/apple/phase5/macos/Unreal Tournament 3.app`. Source preparation, DXVK and OpenAL builds used independent Phase 5 output directories. Commands and toolchain configuration are recorded in [the build plan](BUILD_PLAN.md). The [removal manifest](REMOVAL_MANIFEST.md) describes each source and runtime dependency decision.

| Check | Observed result and local evidence |
| --- | --- |
| Apple dependency closure | PASS. `closure-final.log` checked 2,090 app/headless/test compilation commands, 143 DXVK commands, 104 OpenAL commands, recorded Ninja include dependencies and link commands. Mach-O arm64 slices, imported symbols and load commands were checked for the app, headless executable, both bundled libraries, Vulkan loader and both SDK ICDs. No Android SDK, NDK, JNI, Android WSI, system DSO or source input was found in the tested Apple closure. |
| Native runtime | PASS. `headless-console.log` records PE binding, DLL/TLS startup, heap access and static function lookup. |
| Native CTest suite | PASS, 7/7, final run 0.48 seconds. `ctest-final.log` covers guest VM, named events, critical sections, socket events/readiness and DirectSound capture/device fixtures. |
| Original input and generation checks | PASS, 7/7. `lift-tests.log` uses explicit local game and pinned VC80 paths. The first attempt exposed hard-coded Windows input paths and a missing private research catalog. The fixture now accepts local inputs and derives missing external image sizes from hash-verified PE headers. |
| AppKit and early quit | PASS. `shell-console.log` reports window/drawable sizing, keyboard, mouse, focus release and XInput snapshot. `early-quit-console.log` reports deferred termination and worker completion. |
| D3D9 and graphics | PASS. `d3d-console.log` records COM, depth/BC formats, SM3, draw, occlusion and presentation checks, followed by reset/GetBackBuffer/Present at 1280×720 and 1920×1080. Vulkan validation produced zero VUID errors. |
| Normal folder selection and main menu | PASS through native app launch and the folder picker. The original UT3 installation opened the saved-key login page, Play Offline reached the main menu, mouse input opened Settings, and Escape returned. Instant Action selected Deathmatch and Deck, and Start Game loaded Deck. The initial Terminal `open -n -W` invocation returned LaunchServices error -10810. Native app launch then succeeded, so the original Terminal launch attempt remains a recorded failure. |
| Deck from Instant Action | PASS. Keyboard movement changed the player's view/location, mouse fire reduced ammo from 50 to 48, bots played, and Command-Q completed guest ExitProcess with status 0. `deck-guest.log` and `deck-lifecycle.log` preserve the menu/map and teardown records from the default user-data directory. |
| First 1080p Morbias run | PASS. Rendering, movement, firing and damage were observed. The game subsequently performed server travel to DM-DarkMatch. Command-Q completed guest ExitProcess with status 0. `morbias-console.log` and `morbias/shell.log` retain the run. |
| Repeated startup and completed Morbias round | PASS. The isolated repeat profile started at 1920×1080. Movement and firing worked, and the end-of-round scoreboard showed Harbinger with three kills against the three-frag goal. Command-Q exited with shell status 0. `repeat1-console.log`, `repeat1-guest.log`, `repeat1-shell.log` and `repeat1-status.txt`. |
| Same-profile Deck restart and window close | PASS. Relaunch reused the same profile at 1920×1080, loaded Deck, accepted input and reached a three-frag scoreboard with Evolution on three kills. Command-W closed the native window, deferred termination to the engine, and exited with shell status 0. `repeat2-console.log`, `repeat2-status.txt` and `repeat/shell.log`. Both repeated runs logged input/window disconnection with no runtime worker outstanding. |
| Real audio on both repeated runs | PASS. Morbias recorded 9,690 CoreAudio callbacks and 9,067,461 nonzero samples. Deck recorded 12,503 callbacks and 11,844,586 nonzero samples. Both reported zero nonfinite samples and zero guest OpenAL errors at 96 kHz stereo. The meter reports xruns as unavailable (-1), and no acoustic loopback measurement was taken. |
| Saves and archive preservation | PASS. `zip-regression.log` records the existing profile/campaign write, flush, rename, copy and case-insensitive read fixture, including a fresh-process reopen and unchanged original archive bytes. |
| Native power replacement | PASS. `power.log` records the M4 IOKit snapshot with AC=1, no internal battery (128), unknown battery percentage (255). Linux sysfs power queries are excluded from the Apple compile branch. |
| Android reference preservation | Source selection retains all 80 original host translation units in the original order, using shared engine sources plus retained Android backends. The Android WSI and four pinned DXVK overlay hashes match. A full APK rebuild with the original Windows/NDK toolchain was outside this M4 run. |

### Known failures and remaining risks

The early source relocation missed the portable texture header `tvtx.h`, and the first clean core build failed at that include. The header was relocated with `ut3tx.h`, the Android converter include was updated, and the subsequent complete build passed.

The two final gameplay shutdowns each logged 1,472 rejected HeapFree requests during DLL detach. The saved Phase 4 `repeat-match.log` contains the same count and warning pattern, followed by exit 0. These remain an unresolved teardown diagnostic. UE3 also logs optional VoiceInterface and online-session cleanup warnings during offline play. The tests established orderly worker/window teardown and process exit. They did not establish leak-free teardown.

Physical controller gameplay, microphone capture, Bink playback, external-display changes, MoltenVK game compatibility, and an Android APK rebuild remain outside this run. The gameplay checks use the established KosmicKrisp/CoreAudio path and `-nomovie`. Performance investigation remains deferred. Phase 6 requires separate approval.


## Phase 6 physical-device results (2026-11-17)

See [PHASE6_STATUS.md](PHASE6_STATUS.md) for the full measured matrix and log paths. Real iPhone17 Pro Max: 16 KiB VM probe passed at 0x7000000000; original PE/DLL/TLS/heap/static-entry self-test passed, status 0; MoltenVK clear/readback/presentation passed at 2868x1320. D3D9 device creation failed, HRESULT 8876086a, because robustBufferAccess2 and nullDescriptor are unavailable. No first UT3 game frame, iOS gameplay/input/audio, suspension or thermal/performance success is claimed. Existing macOS regression results and sandbox-limited failures are recorded in that report.


## Phase 6 continuation: explicit D3D9 compatibility

The initial missing-feature failure is superseded by the D3D9 fallback in [D3D9_PORTABILITY.md](D3D9_PORTABILITY.md). Driver capability bits remain false; explicit constant bounds and typed read-only dummy descriptors supply the required D3D9 behavior. Exact ARGB tests, dynamic sampler selection, COM creation/draw/query/Present and 720p/1080p resets pass with Metal API/GPU validation. An ordinary run captured the first real UT3 back buffer on the iPhone. Real-game validation then caught heap aliasing during upload; the dedicated-image correction now passes two real-game frame-capture/exit runs with Metal API and GPU shader validation enabled. The original aliasing assertion did not recur. Existing guest DLL-detach heap-free warnings remain documented. Full Phase 6 gameplay/input/audio/lifecycle remain pending, and Phase 7 is not started.


## File-based CD key support (2026-11-18)

Completed on macOS and the physical iPhone: the owner-provided `cdkey.txt` passes the original game validator and reaches Login. A synthetic invalid key is rejected. The Mac file-mode backend prevents legacy Keychain authentication UI while retaining records and restoring the previous interaction setting. Native input/audio/gameplay remain Phase 6 work; Phase 7 is not started. File locations, preserved ABI/validation, exact tests, remaining limitations and evidence are in [CDKEY_FILE.md](CDKEY_FILE.md).


## Phase 6 gameplay continuation (2026-11-18)

The native UIKit keyboard, GameController/XInput bridge and pinned OpenAL Soft RemoteIO backend are implemented. The owner verified keyboard typing/deletion/Done, clear sound and a full offline match with GameSir X5 Lite. The owner also verified correct touch selection, keyboard operation, one-second Keyboard button disappearance, and audible sound/controller recovery after restoring the app. Explicit foreground audio-session/device recovery is implemented; external route changes, interruptions and memory pressure remain unverified. Earlier pending statements above describe previous checkpoints. [Current evidence, exact commands, source boundaries and unresolved issues](IOS_GAMEPLAY.md). Phase 7 has not started.


## iOS resolution and icon continuation (2026-11-18)

The ordinary launcher no longer forces 640x480 over the saved UE3 resolution. The updated phone launch uses its existing 1280x720 setting; successful iOS back-buffer changes update the full-surface cursor clip. The supplied icon now compiles into the signed iOS bundle. All 12 native host tests pass. The owner verified touch coverage at 1920x1080, a visible Home Screen icon and, after rechecking an initial contrary report, saved resolution persistence. No additional runtime change was required. [Diagnosis, exact commands, changed files and device evidence](IOS_RESOLUTION.md). Phase 7 has not started.

## Phase 7 iPhone performance update

See [PHASE7_STATUS.md](PHASE7_STATUS.md) for the 720p/60 FPS target, exact commands, pinned dependency continuity, measured results, optional experiments and remaining failures.

## Simple builds and final directory cleanup

The owner-authorized root Android removal and two-command Apple build path are documented in [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md). Use [BUILDING.md](../../BUILDING.md) for current beginner instructions; older Android-reference/build statements above describe earlier checkpoints.

## Visible data folder update — 2026-11-19

Current macOS/iOS paths, safe legacy migration, remembered Mac installation, build 9 tests and SideStore verification status are in [DATA_LOCATIONS.md](DATA_LOCATIONS.md). Older Documents/Game and Application Support instructions above describe earlier builds.
