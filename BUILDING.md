# Build Unreal Tournament 3 on Apple Silicon

Use your own **Steam UT3 Windows installation**. The game folder must contain `Binaries`, `Engine` and `UTGame`. Modified executables are rejected. This builds the existing native ARM64 engine; no Wine, Rosetta, VM or x86 emulation is required.

## One-time setup on the Mac

1. Install full **Xcode** (27.2 is the tested version), open it once, and finish its component/license setup. Select it in Xcode → Settings → Locations → Command Line Tools. Both builds run on an Apple Silicon Mac.
2. Install [Homebrew](https://brew.sh/) if needed, then run:

   ```sh
   brew install python@3.13 cmake ninja wimlib
   ```

3. Download/clone this repository, open Terminal in its folder, and run one of the commands below. Keep the quotes around a path containing spaces. You can drag a folder from Finder into Terminal to insert its path.

The scripts create their own Python environment, fetch exact hash-pinned dependencies, verify your game inputs, reuse or generate the static recompilation, and compile/package the app. First builds and downloads take longer; later runs reuse cached work. You do not need to edit CMake files or provide an Apple signing account to create an IPA.

The first preparation may download the pinned Vulkan SDK and a **5.1 GB Microsoft evaluation ISO** to extract two exact VC80 runtime files. It reads the ISO as data; it does not install Windows. Existing verified files are reused. Allow space for the ISO, extracted WIM, SDK, generated sources and build outputs, in addition to the original game. The measured generated tree is about 834 MiB, with native build trees about 1–2.5 GiB each on the development M4. Keep the source checkout/build files if you need to rebuild or replace a library.

## macOS

```sh
./build_macos.sh "/path/to/UT3"
```

Result:

```text
dist/macos/Unreal Tournament 3.app
```

Open the app and select your original game folder once; the location is remembered for later launches. The app creates **Documents/Unreal Tournament 3/UserData** for profiles/settings/logs. Put **cdkey.txt** in **Documents/Unreal Tournament 3**, next to UserData. The previous Application Support data is moved to UserData only when that destination is absent or empty; populated conflicts are preserved separately. Game assets stay outside the app. Vulkan loader, KosmicKrisp/MoltenVK runtime libraries, DXVK and OpenAL are included in the app; it does not need the development SDK path afterward. The build runs native regression tests and the original headless runtime self-test before packaging. The output is locally ad hoc signed, not notarized for public distribution. macOS build 14 enables Vertical Sync and a 60 FPS cap by default. The **Graphics** menu lets you select KosmicKrisp or MoltenVK and toggle Vertical Sync; restart the game to apply changes. Both backends are bundled, and controller vibration uses the shared Apple haptics implementation. Advanced `DXVK_CONFIG`, `UT3_FPS_LIMIT`, and explicit Vulkan-driver environment overrides take precedence.

## iPhone and iPad / SideStore IPA

```sh
./build_ios.sh "/path/to/UT3"
```

Result:

```text
dist/ios/Unreal Tournament 3.ipa
```

This is an **unsigned physical-device ARM64 IPA** with the standard `Payload/*.app` layout. Import it into SideStore, which signs it with your account before installation. Building does not install it on a phone, require a provisioning profile, or access your signing keychain. See [SideStore's installation guide](https://docs.sidestore.io/docs/installation/install.html) and [FAQ](https://docs.sidestore.io/docs/faq) for SideStore setup and account/device limits. Creating and inspecting an IPA is separate from testing SideStore's signing/install flow.

The IPA is deliberately small: **no original UT3 assets, CD key or saves**. For the first installation:

1. Launch once. The app creates **Game**, **UserData** and a readme directly in its shared files. iOS already labels this app's container **UT3**—there is no second folder with that name.
2. In Files, open **On My iPhone/iPad → UT3** (the app), or select **iPhone/iPad → Files → UT3** in Finder. Put your **Game** folder and private **cdkey.txt** directly there, beside UserData:

   ```text
   UT3                      ← iOS app container shown in Files/Finder
     Game/
       Binaries/UT3.exe
       Engine/
       UTGame/
     UserData/
     cdkey.txt
     READ ME.txt
   ```

3. Relaunch UT3. Do not add a Documents folder or another Unreal Tournament 3 folder. Internally iOS calls these shared files Documents; that internal name is not an extra user-created directory.

Build 10 safely lifts files from build 9's redundant inner folder into the shared top level. It moves within the container rather than copying the game. Populated conflicts are preserved in **Previous Layout Backup**, never overwritten or merged into saves; once migration completes the duplicate named folder is removed. The original flat layout from older builds is accepted directly. Profile/config locations under UserData remain `Documents/My Games/Unreal Tournament 3/UTGame/SaveData` and the adjacent `Config`.


The native Keyboard button opens text entry; GameSir/MFi input and touch-as-mouse remain supported. Build 13 adds rumble for controllers exposing iOS haptics and restores UT3's missing PC force-feedback backend automatically. Keep Controller Vibration enabled in the game; GameSir X5 Lite has no motors. Existing user configuration is backed up before the backend repair; original game inputs are unchanged. See [controller vibration validation](docs/apple/CONTROLLER_HAPTICS.md). Prefer 1280×720 at the default 60 FPS cap; 1920×1080 remains selectable. Update through the same SideStore app identity; do not uninstall the existing installation for an update.

Build 12 declares native iPhone and iPad support in the same IPA. iPad uses a resizable native window rather than the iPhone compatibility box. The game image preserves its aspect ratio, so a widescreen game resolution can leave bars on an iPad. The audio session mixes with other apps, allowing music to continue while playing; UT3 still pauses its own audio when backgrounded. Physical Spotify coexistence and M2 iPad presentation need owner verification after the SideStore update.

The tested device is iPhone 17 Pro Max on iOS 27.0.1. The build's iOS 18 deployment minimum does not establish compatibility with older devices/OS versions.

## If a build stops

Fix the reported error and run **the same command again**. The scripts keep cached dependencies and compiler outputs. Original game files are read-only inputs. They never print or bundle your CD key.

Useful optional arguments:

```sh
./build_ios.sh "/path/to/UT3" --check
./build_macos.sh "/path/to/UT3" --jobs 4
./build_ios.sh "/path/to/UT3" --offline
./build_ios.sh "/path/to/UT3" --vc80-root "/path/to/exact/VC80/files"
```

`--check` verifies prerequisites and inputs without compiling; missing dependency preparation may still download files. `--offline` refuses network downloads, including missing Python packages. `--vc80-root` must contain the exact x86 8.0.50727.9680 `msvcr80.dll` and `msvcp80.dll` pinned in `config/modules.json`; the older Steam redistributable is not a substitute. `--sdk` selects an existing **pinned** SDK macOS folder. `--windows-iso` accepts the matching official evaluation ISO you already downloaded. `--help` lists advanced options; ordinary builds need only the game-folder argument.

First-time paths without cached dependencies have separate preparation costs. Tested results, failed attempts and remaining device/installer limits are recorded in [the cleanup/build report](docs/apple/CLEANUP_BUILD_STATUS.md). Builds target Apple Clang; replacing Xcode's compiler or changing pinned dependencies is outside this simple path.

## Ownership and licenses

Use your own game and key. The generated executable contains statically translated game code; an asset-free IPA is not a grant of redistribution rights. Keep personal builds private unless you have the necessary rights. Original binaries, keys and game assets are not published by these scripts. Third-party notices are included with packaged apps; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the dependency/source manifests before distributing any derivative. Dependency downloads retain their original license terms.
