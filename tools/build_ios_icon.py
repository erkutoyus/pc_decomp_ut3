"""Compile the owner-supplied icon into an iOS app with Apple's asset compiler."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--png", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    catalog = args.work / "UT3.xcassets"
    icon = catalog / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    metadata = {"version": 1, "author": "xcode"}
    (catalog / "Contents.json").write_text(json.dumps({"info": metadata}))
    shutil.copyfile(args.png, icon / "AppIcon1024.png")
    (icon / "Contents.json").write_text(json.dumps({"info": metadata, "images": [
        {"filename": "AppIcon1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    ]}))
    partial = args.work / "icon-info.plist"
    subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(args.app),
                    "--platform", "iphoneos", "--minimum-deployment-target", "18.0",
                    "--target-device", "iphone", "--target-device", "ipad",
                    "--app-icon", "AppIcon", "--output-partial-info-plist", str(partial),
                    "--warnings", "--errors"], check=True)
    info_path = args.app / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    generated = plistlib.loads(partial.read_bytes())
    if "CFBundleIcons" not in generated or not (args.app / "Assets.car").is_file():
        raise SystemExit("actool did not produce the iOS app icon and asset catalog")
    info.update(generated)
    info_path.write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    main()
