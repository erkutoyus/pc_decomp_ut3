# Visible data folders and remembered installation — updated 2026-11-23

**Current iOS layout: build 11 and later.** The Files/Finder app container is labelled UT3. Game, UserData and cdkey.txt belong directly inside it; the app no longer creates a second named folder. The macOS Documents layout and remembered selection remain unchanged. The build 9 account below is historical.

Version 10 migration moves the redundant inner folder's Game/UserData into absent or empty top-level destinations, lifts other nonconflicting files, and removes the empty inner directory. Any conflicts remain intact in a uniquely named Previous Layout Backup. It does not overwrite profiles/keys or copy multi-GB assets. Native first-launch, nested-to-flat, conflict-backup and repeated-launch tests passed; M4 CTest remains 16/16 PASS. The current SideStore build 9 self-test invocation logged that it could not find its expected executable. Device enumeration confirmed empty Game/UserData directories after the owner's folder changes; no graphics initialization or first game frame was reached in that invocation. This is evidence of missing/misplaced inputs, not proof that no later rendering problem exists. Build 10 is packaged with the same pre-SideStore bundle identifier. Its IPA Payload/CRC checks and 19 selected Python regressions pass. Subsequent device checks passed the original headless self-test and D3D9 fixture and captured a real 1280×720 UT3 login frame (game exit status 0). The first validated game frame took 51.866 seconds from bridge initialization; build 11 keeps a loading message visible until an accepted Present. The owner confirmed build 11 works with the UT3 app/container name. These results supersede the earlier pending verification. The owner independently confirmed the macOS app works correctly; its paths/selection behavior are unchanged in this correction.


The owner requested a visible `Unreal Tournament 3` folder on both platforms, with UserData/key colocated, an automatically created iOS Game folder, and remembered macOS game selection. The earlier screen exposed the internal container name `Documents`, which was misleading in Finder/Files.

## Build 9 layout (iOS superseded by build 10 above)

macOS creates `~/Documents/Unreal Tournament 3/` before asking for a game installation. It contains `UserData`, `READ ME.txt`, the optional private `cdkey.txt`, and an atomically saved `GameFolder.bookmark`. The selected installation stays where the owner chose it. Subsequent normal launches resolve the bookmark; a missing/unreadable installation returns to the picker. CLI `--data` remains an explicit isolated override and does not migrate or rewrite the owner's default selection.

Inside the iOS app's shared files, first launch creates:

```text
Unreal Tournament 3/
  Game/                  # Binaries/UT3.exe, Engine, UTGame
  UserData/
  cdkey.txt              # owner supplies this; never bundled
  READ ME.txt
```

Do not create a folder named Documents. The app's private Documents URL is the backing location for its Finder/Files shared container. A similarly named directory in another app/provider is not the UT3 app's shared container. Open the actual UT3 app in Files/Finder, then use the folder the app created. Finder may also drop Game/cdkey.txt at the shared top level; the compatibility migration adopts Game into an empty canonical destination at next launch.

Profile files remain at `UserData/Documents/My Games/Unreal Tournament 3/UTGame/SaveData`; INI files are in the adjacent `Config` directory. This preserves the original guest file-system mapping and game profile behavior rather than changing guest paths.

## Migration and key behavior

`platform/apple/DataPaths.{h,m}` contains shared Foundation path preparation and macOS bookmark storage. Old iOS top-level Game/UserData and old macOS Application Support user data move into absent or empty destinations. Populated conflicting trees are not merged or overwritten; the old tree stays available. Empty destination removal is limited to a directory whose contents were checked empty. Invalid legacy file-in-place-of-folder layouts fail without moving the file.

A bounded, regular legacy cdkey.txt may be copied to the new root only when no canonical key exists. Original legacy keys remain intact. New-root, game-root and UserData key lookup still calls the unchanged original UT3 validator; neither file presence nor successful copying validates a key. No key contents are logged or embedded. Bookmarks are regular file-location bookmarks (this app does not enable App Sandbox); disk writes are atomic and independent of deferred preferences flushing before guest `_exit`.

Source changes: shared DataPaths helper; AppKit default/migration/selection lifecycle; UIKit folder creation, waiting-screen wording and root selection; both CMake source lists; build 9 iOS metadata; native path/migration/bookmark tests; beginner instructions/build output text. The engine, guest ABI, graphics compatibility, profile format and key validator are unchanged.

## Actual checks

- Native path fixture PASS: first-launch directories/readme, empty-destination adoption, old game/profile/key preservation, repeated calls, populated conflicts, migrated macOS legacy data, atomic bookmark re-read, missing selected executable, invalid directory layout. The initial test helper used POSIX read/write names and failed compilation; those fixture helper names were corrected.
- M4 CTest: **16/16 PASS**, including the new Foundation fixture and existing VM/input/threading/audio/ZIP/query-adjacent tests. Standalone fixture also passed; restricted execution printed sandbox-extension warnings while creating ordinary bookmarks, and the full native suite with required access passed.
- Actual default Mac app: launch with the owned game path, create/migrate Documents root, accepted native Presents, orderly exit 0; second launch without game/data arguments logs `Using saved game folder location.`, uses the requested Documents UserData path, presents and exits 0. These are front-end startup/relaunch checks, not a new full-match claim.
- macOS and physical-device iOS builds linked with the root Android directory absent. Their compile/Ninja/import closures passed: 2,104 macOS and 2,084 iOS app/test commands, 143 per DXVK build and 104 per OpenAL build; no Android dependency was found. The 19 selected Python regressions also pass. Original generated game code and dependency revisions are retained.
- IPA build 9: physical-device ARM64, Payload/CRC checks and stable default `org.ut3.port.ios` identity before SideStore signing. No game files, keys, profiles or development provisioning material are included.

The actual SideStore-installed app was identified as `org.ut3.port.ios.7PRB6X3L89`, build 8. CoreDevice enumerated **zero files** in that app's Documents container before this update. That proves the copied assets were not present in that installation's shared container; it does not establish whether a later game-runtime failure exists after copying them correctly. CoreDevice subsequently confirmed an in-place SideStore update to build 9. The canonical shared Unreal Tournament 3 folder is present and now contains Game, restored UserData and cdkey.txt; no key contents were read or printed. Subsequent container listings returned CoreDevice StreamingAction error 3 while the same build 9 app remained installed; no launch success is inferred from that metadata. The owner readiness/unlocked-device launch check remains pending; no Xcode-profile installation is substituted for SideStore validation.

Evidence is retained locally under `build/apple/cleanup/`: `paths-{macos,ios}-*-build.log`, `paths-native-tests.log`, `data-paths-{compile,test}.log`, `mac-paths-relaunch.log`, `paths-mac-relaunch-{1,2}.log`, `sidestore-{apps,files}-nov19.json`, package/closure logs and the unsigned IPA receipt in `dist/ios/`. Original data stays private.

## Android follow-up

The root `android/` tree is absent. The removal manifest lists all **41** preserved shared moves; each destination exists. The original Android bytes remain in the hash-verified local reference archive, with source history retained by Git. Obsolete activity/JNI/WSI/launcher/APK recipes were retired; useful native/texture/ZIP/script fixtures and the ABI helpers are in the shared tree. Android/NDK references in vendored provenance or target-guarded legacy code are not Apple build dependencies. See [REMOVAL_MANIFEST.md](REMOVAL_MANIFEST.md) and [CLEANUP_BUILD_STATUS.md](CLEANUP_BUILD_STATUS.md).

## Commands

```sh
cmake --build build/apple/macos --parallel 8
ctest --test-dir build/apple/macos --output-on-failure
cmake --build build/apple/ios --parallel 8
./build_macos.sh "/path/to/UT3"
./build_ios.sh "/path/to/UT3"
```

Packaging uses the existing pinned Vulkan/DXVK/OpenAL builds and `tools/package_ipa.py`. See [BUILDING.md](../../BUILDING.md) for the updated Finder/Files layout and one-time requirements. Build 9 should update through the same SideStore identity; do not delete the installed app to apply the update.
