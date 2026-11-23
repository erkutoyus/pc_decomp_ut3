"""Package a native CMake iOS app using an Xcode-provisioned development app."""
import argparse
import plistlib
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--provisioned-app", type=Path, required=True)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.app.resolve() == args.output.resolve():
        parser.error("--output must be a separate staging directory")
    profile_app = args.provisioned_app
    source_info = plistlib.loads((args.app / "Info.plist").read_bytes())
    profile_info = plistlib.loads((profile_app / "Info.plist").read_bytes())
    if source_info["CFBundleIdentifier"] != profile_info["CFBundleIdentifier"]:
        parser.error("the app and Xcode provisioned app must have the same bundle identifier")
    signature = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(profile_app)],
        check=True, capture_output=True,
    )
    try:
        entitlements = plistlib.loads(signature.stdout)
    except plistlib.InvalidFileException:
        parser.error("codesign returned no valid entitlements; check the provisioned app signature and keychain access")
    shutil.copytree(args.app, args.output, dirs_exist_ok=True)
    # Device families belong to this app, not the provisioning scaffold.
    for key in ("CFBundleSupportedPlatforms", "MinimumOSVersion", "DTPlatformName", "DTSDKName"):
        if key in profile_info:
            source_info[key] = profile_info[key]
    (args.output / "Info.plist").write_bytes(plistlib.dumps(source_info))
    shutil.copyfile(profile_app / "embedded.mobileprovision", args.output / "embedded.mobileprovision")
    signed_entitlements = args.output.parent / (args.output.stem + "-entitlements.plist")
    signed_entitlements.write_bytes(plistlib.dumps(entitlements))
    for framework in sorted((args.output / "Frameworks").glob("*")):
        subprocess.run(["codesign", "--force", "--sign", args.identity, "--timestamp=none", str(framework)], check=True)
    subprocess.run(["codesign", "--force", "--sign", args.identity, "--entitlements", str(signed_entitlements),
                    "--timestamp=none", str(args.output)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(args.output)], check=True)
    print(args.output)


if __name__ == "__main__":
    main()
