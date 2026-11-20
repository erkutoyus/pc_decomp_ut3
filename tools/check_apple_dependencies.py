"""Audit the compile inputs, native imports, and Vulkan driver paths of an Apple build."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ANDROID = re.compile(
    r"(?:^|[/\s=])android/(?:host|app|launcher|dxvk|runtime|texconv|uscript)/"
    r"|(?:^|/)android/(?:sdk|ndk)/|aarch64-linux-android|ndk/\d+\."
    r"|(?:\.so(?:\s|$)|\bJNI_OnLoad\b|\b_?Java_\w+|\b_?ANativeWindow\w*"
    r"|\b_+android_log_\w+|\b_?APerformanceHint_\w+)", re.IGNORECASE,
)


def output(*command):
    return subprocess.check_output(list(map(str, command)), text=True, errors="replace")


def require_apple(text, label):
    for line in text.splitlines():
        if ANDROID.search(line):
            raise SystemExit(f"{label}: Android dependency: {line.strip()}")


def inspect_build(build):
    compilation = build / "compile_commands.json"
    commands = json.loads(compilation.read_text())
    if not commands:
        raise SystemExit(f"{compilation}: empty compilation database")
    deps = output("ninja", "-C", build, "-t", "deps")
    if not deps:
        raise SystemExit(f"{build}: missing recorded Ninja dependencies")
    require_apple(compilation.read_text(), compilation)
    require_apple(deps, f"{build} Ninja dependencies")
    require_apple(output("ninja", "-C", build, "-t", "commands"), f"{build} Ninja commands")
    print(f"{build.relative_to(ROOT) if build.is_relative_to(ROOT) else build}: "
          f"{len(commands)} commands checked with recorded dependencies")


def inspect_binary(binary):
    architectures = output("lipo", "-archs", binary).split()
    if "arm64" not in architectures:
        raise SystemExit(f"{binary}: expected an arm64 slice, got {architectures}")
    deps = output("otool", "-arch", "arm64", "-L", binary)
    require_apple(deps, binary)
    require_apple(output("nm", "-arch", "arm64", "-g", binary), binary)
    print(deps.rstrip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--dxvk-build", type=Path, required=True)
    parser.add_argument("--openal-build", type=Path, required=True)
    args = parser.parse_args()
    for build in (args.build, args.dxvk_build, args.openal_build):
        inspect_build(build.resolve())

    app = args.build / "Unreal Tournament 3.app"
    ios = not (app / "Contents").is_dir()
    contents = app if ios else app / "Contents"
    plist = plistlib.loads((contents / "Info.plist").read_bytes())
    bundled = sorted((contents / "Frameworks").glob("*"))
    if {path.name for path in bundled} != {"libdxvk_d3d9.dylib", "libopenal.1.dylib"}:
        raise SystemExit(f"Unexpected bundle frameworks: {bundled}")
    binaries = [contents / plist["CFBundleExecutable"] if ios else contents / "MacOS" / plist["CFBundleExecutable"], *bundled]
    if not ios:
        sdk = Path(plist["UT3VulkanSDKPath"])
        if not sdk.is_absolute():
            sdk = contents / "Resources" / sdk
        icds = sdk / "share/vulkan/icd.d"
        drivers = []
        for name in ("libkosmickrisp_icd.json", "MoltenVK_icd.json"):
            manifest = icds / name
            library = Path(json.loads(manifest.read_text())["ICD"]["library_path"])
            drivers.append((manifest.parent / library).resolve())
        binaries += [args.build / "ut3-runtime-selftest", sdk / "lib/libvulkan.1.dylib", *drivers]
    for binary in binaries:
        inspect_binary(binary)



if __name__ == "__main__":
    main()
