# cdkey.txt support — 2026-11-18

## Result and use

Verified on the M4 and physical iPhone 17 Pro Max: the owner's file passes the **original game validator** and UT3 renders the Login screen without asking for the CD key. The key was not printed, hashed into diagnostics, embedded in the app, or copied into source/generated code. A synthetic formatted invalid key was rejected by that same validator and stayed on the CD Key screen.

- **macOS:** keep `cdkey.txt` in the selected UT3 game directory (the directory containing `Binaries`, `Engine` and `UTGame`). This session uses `/Volumes/NVME512/Github/UT3/cdkey.txt`. A file in the selected writable user-data directory is the fallback.
- **iPhone:** the file is installed as `Documents/cdkey.txt` in the native app container. This is the app's shared Documents folder, accessible through Files/Finder file sharing. It is already copied for this device. Lookup order is Documents, Game, UserData. App updates preserved it in the tests.
- Use one plain-text ASCII/UTF-8 line in `XXXX-XXXX-XXXX-XXXX` form. A UTF-8 BOM, surrounding whitespace, lowercase letters and a compact 16-character form are accepted and normalized. Files larger than 256 bytes, symlinks, multiple lines of keys and malformed contents are rejected without falling through to another saved key.
- Restart after editing the file. A process holds a snapshot and caches the original validator's result for the game's product ID. Keep the file for subsequent launches; it is not imported into Keychain.
- A normal iPhone app launch now starts UT3. `--selftest` retains the original runtime-only check; `--validate-d3d9` and `--validate-vulkan` retain their diagnostics. Frame capture remains opt-in. This remains the Phase 6 graphics/input/audio bring-up app, not a completed iOS gameplay port.

## Validation and ABI

`platform/apple/ProductKey.c` is an optional data-source adapter, not an authorization bypass. The pinned UT3 `SetProductKey` routine calls the original cdecl validator at **0x01228D20** with the ANSI key and the subsystem's 16-bit product ID at offset **0x27c**. The file adapter calls that exact statically compiled routine before returning bytes. The result is cached only for that file snapshot/product ID. A successful file read or a syntactically valid key does not imply acceptance.

The adapter is registered for the original `GetProductKey` reader at **0x0120E200**. Both entries have byte-prefix and dispatch guards against the pinned original image. The output ABI remains BOOL, thiscall, exactly 19 ANSI bytes without a NUL, and `ret 8`. Output capacity and guest writability are checked. Temporary guest buffers are wiped and freed; caller CPU state is saved/restored around the original validator. `IsKeyValid`, `SetProductKey`, network authentication, and the validator itself are not patched or replaced.

Four direct same-unit reader calls would otherwise bypass the dispatch table. The Apple source preparer redirects those calls through the existing full-register `RECOMP_ICALL` path. The original generated getter body remains available. No original binary is modified, no x86 emulation/JIT is introduced, and unrelated lifted-code optimizations remain in place. The Apple preparer includes the new override in its full calling-contract set.

Without a file, the original reader and existing Keychain path remain available. With a malformed/unreadable file, startup reports an error without showing its contents. With a well-formed but invalid key, the original validator rejects it and the game remains at the CD Key screen.

## macOS Keychain behavior

Fresh-data tests made no Keychain requests. The owner's existing Mac profile also performs an additional legacy protected-data read after accepting the file key. Merely adding a new CD-key source did not eliminate that lookup. We therefore serialized the existing backend's operations and, **only in file mode**, temporarily disallowed legacy Keychain interaction during each operation and restored the previous process setting afterward.

This uses the legacy Keychain interaction APIs because the existing records live in the login keychain; the Security SDK explicitly says modern no-authentication-UI query attributes do not prevent prompts for legacy items. No records are deleted, rewritten, or unlocked. Already-authorized accesses may succeed silently. A protected-data read that requires authorization returns an error without a dialog; its contents are not fabricated. Removing the file restores the prior interactive policy on subsequent launch. The exact field responsible for the additional existing-profile read was not identified; it is separate from the successfully validated file-reader path.

Actual saved-profile test output:

```text
[protected-data] Keychain trace enabled
[product-key] using owner-provided cdkey.txt; original game validation unchanged
[product-key] original game validator accepted cdkey.txt
[protected-data] Keychain read completed: interaction=forbidden status=-25293
```

UT3 subsequently rendered Login. The failed optional legacy read is preserved as a real result, not reported as successful password retrieval. The no-UI setting is scoped to this application's backend operation, not a persistent system preference. The Keychain policy fixture tests original behavior without a file, previous-allowed/previous-disallowed restoration, API failures, result cleanup and concurrent serialization without touching the real Keychain.

## Files changed

- `platform/apple/ProductKey.{c,h}`: bounded file parser, original-validator invocation/cache, pinned reader adapter.
- `engine/host/main.c`: install the optional Apple adapter after PE/dispatch initialization.
- `tools/prepare_macos.py`: four same-unit calls use the existing indirect ABI path.
- `platform/apple/Application.m`: configure the optional file source and report malformed files.
- `platform/apple/ios/Application.m`: configure app-container lookup, normal game launch, explicit self-test and opt-in captures.
- `platform/apple/ProtectedData.m`: file-mode scoped noninteractive legacy operations and opt-in content-free diagnostics.
- `CMakeLists.txt`: shared Apple source, preparer input and two regression fixtures.
- `tests/test_product_key_file.c`, `tests/test_keychain_interaction.m`: synthetic parser/ABI/validation and no-UI boundary tests.
- `.gitignore`: private key files excluded and Objective-C test allowlist; Apple documentation updated.

## Commands and evidence

Local artifacts below are under `build/apple/phase6/product-key/` and are excluded from publication. The owner's key is not a command argument.

```sh
cmake --build build/apple/phase5/macos --parallel 8
cmake --build build/apple/phase6/ios --parallel 8
ctest --test-dir build/apple/phase5/macos --output-on-failure
clang -std=c11 -g -fsanitize=address,undefined -UNDEBUG -Iengine/host \
  tests/test_product_key_file.c -o build/apple/phase6/product-key/unit-asan
build/apple/phase6/product-key/unit-asan
```

Use the existing Phase 6 signing/package procedure in [BUILD_PLAN.md](BUILD_PLAN.md). Copy the owner's source file to `Documents/cdkey.txt` with `devicectl device copy to` for bundle `org.ut3.port.ios.probe`; no file content is printed. Physical tests use that bundle and the paired iPhone.

```sh
UT3_TRACE_KEYCHAIN=1 \
  'build/apple/phase5/macos/Unreal Tournament 3.app/Contents/MacOS/Unreal Tournament 3' \
  --game /Volumes/NVME512/Github/UT3 --capture-first-frame
```

The default Mac user-data location is used in the final saved-profile test. `UT3_TRACE_KEYCHAIN` logs only operation/policy/status, never data or tokens. Private logs are scanned locally for the key text before any filtered excerpts are displayed.

| Check | Actual result / evidence |
| --- | --- |
| Parser and x86 boundary | PASS: normalization, precedence, malformed/oversized/symlink rejection, output bounds/no extra NUL, original fallback, pinned reader/validator guards, original validator rejection, CPU-state preservation and guest-buffer cleanup. |
| Address/undefined sanitizer fixture | PASS, synthetic data only. |
| Same-unit routing | Four direct reader calls redirected; original getter body and original validator calls retained. |
| Full macOS CTest | **9/9 PASS**, `macos-final-tests.log`. |
| Mac fresh state with owner's file | Original validator accepted, Login frame captured; trace enabled, no Keychain operation requested. `macos-console.log`, `macos-key-file-screen.png`. |
| Mac saved profile with final no-UI policy | Original validator accepted, legacy read returned authorization failure with interaction forbidden, Login frame captured. `macos-noninteractive-console.log`, `macos-existing-profile-screen.png`. |
| Invalid-key control | Original validator rejected synthetic file and rendered CD Key. `invalid-console.log`, `invalid-key-screen.png`. Owner's source file unchanged. |
| iPhone file and app-update persistence | Original validator accepted on repeated launches, Login frame captured and process exited 0. `iphone-console.log`, `iphone-repeat-console.log`, `iphone-key-file-screen.png`. |
| Normal iPhone launch | PASS: no diagnostic arguments, original key accepted and repeated accepted queue presents in `iphone-normal-ut3.log`; launch options in `iphone-normal-launch.json`. The task-owned process was stopped with SIGTERM after this check; this is not claimed as an orderly-shutdown test. |
| Credential-text scan | No key text found in the collected diagnostic/config files. No real key or key-derived fingerprint is printed in this report. |

The normal-launch log check initially searched for a one-time stderr-only marker in the runtime file and failed. The corrected check uses the actual repeated `accepted unique vkQueuePresentKHR` runtime records and the empty diagnostic-argument list in the launch report.

The first iPhone launch was refused while the device was locked. After the owner unlocked it, the actual tests above ran. Initial fixture builds exposed a missing include path and a fixture identifier collision; those were corrected before passing the final tests. No failed product-key validation was changed into success.

## Remaining Phase 6 work

This completes the file-key task. Native iOS keyboard/touch/controller behavior, audio sessions, offline gameplay, lifecycle handling and full resource-ownership validation remain separate Phase 6 work. Existing DLL-detach heap warnings are retained as documented in [D3D9_PORTABILITY.md](D3D9_PORTABILITY.md). No Phase 7 work was started.

## Visible data folder update — 2026-11-19

Current macOS/iOS paths, safe legacy migration, remembered Mac installation, build 9 tests and SideStore verification status are in [DATA_LOCATIONS.md](DATA_LOCATIONS.md). Older Documents/Game and Application Support instructions above describe earlier builds.
