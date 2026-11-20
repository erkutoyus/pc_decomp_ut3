"""Build the pinned OpenAL Soft CoreAudio backend and opt-in callback meter."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
REVISION = "b2c48f7718ef3fcf67921a8b6534c4914e328970"
METRICS = ROOT / "engine/audio"


def replace_once(text, before, after):
    if text.count(before) != 1:
        raise SystemExit(f"Unexpected pinned OpenAL content near {before!r}")
    return text.replace(before, after)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build/apple/openal")
    parser.add_argument("--ios", action="store_true", help="Cross-compile the same pinned CoreAudio backend for iPhoneOS ARM64")
    args = parser.parse_args()
    pins = json.loads((ROOT / "dependencies-audio.json").read_text())["files"]
    archive_pin = pins["reference/openal-soft/openal-soft-1.25.2.tar.gz"]
    if hashlib.sha256(args.archive.read_bytes()).hexdigest() != archive_pin:
        raise SystemExit("OpenAL Soft archive does not match the repository pin")
    build = args.build.resolve()
    source = build.with_name(f"{build.name}-source-{REVISION[:12]}")
    unpacked = build.with_name(f"{build.name}-unpacked")
    with tarfile.open(args.archive) as archive:
        archive.extractall(unpacked, filter="data")
    original = unpacked / f"openal-soft-{REVISION}"
    shutil.copytree(original, source, dirs_exist_ok=True)
    for name in ("metrics.h", "metrics.cpp"):
        metric = METRICS / name
        if hashlib.sha256(metric.read_bytes()).hexdigest() != pins[f"reference/audio-runtime/rebuild/android/audio/{name}"]:
            raise SystemExit(f"Audio meter does not match the repository pin: {name}")
        shutil.copyfile(metric, source / "alc/backends" / name)
    cmake = source / "CMakeLists.txt"
    with cmake.open("a") as output:
        output.write("\ntarget_sources(OpenAL PRIVATE alc/backends/metrics.cpp)\n")
    backend = source / "alc/backends/coreaudio.cpp"
    text = '#include "metrics.h"\n' + backend.read_text()
    text = replace_once(text, "        mDevice->renderSamples(buffer.mData, buffer.mDataByteSize/mFrameSize,\n            buffer.mNumberChannels);",
        """        const auto frames = buffer.mDataByteSize/mFrameSize;
        mDevice->renderSamples(buffer.mData, frames, buffer.mNumberChannels);
        if(FrostpunkAudio_ProbeEnabled())
        {
            const int format = (mFormat.mFormatFlags & kAudioFormatFlagIsFloat) ? 2
                : mFormat.mBitsPerChannel == 16 ? 1 : mFormat.mBitsPerChannel == 32 ? 4 : 0;
            if(format)
                FrostpunkAudio_RecordCallback(buffer.mData, static_cast<int>(frames),
                    static_cast<int>(buffer.mNumberChannels), format, 0, 0, 1, -1, 0, 0);
        }""")
    text = replace_once(text, "    mFrameSize = mDevice->frameSizeFromFmt();\n    AURenderCallbackStruct",
        """    mFrameSize = mDevice->frameSizeFromFmt();
    mFormat = streamFormat;
    FrostpunkAudio_RecordStream(0, 1, static_cast<int>(streamFormat.mChannelsPerFrame),
        static_cast<int>(streamFormat.mSampleRate), 0, 0, 0, 0, 0);
    AURenderCallbackStruct""")
    backend.write_text(text)
    # SDK 27 annotates callback pointers nonblocking. Keep the pinned callbacks
    # and disable the upstream effect-analysis flag that rejects their types.
    platform = ["-DCMAKE_SYSTEM_NAME=iOS", "-DCMAKE_OSX_SYSROOT=iphoneos", "-DCMAKE_OSX_DEPLOYMENT_TARGET=18.0"] if args.ios else []
    subprocess.run(["cmake", "-S", str(source), "-B", str(build), "-G", "Ninja", *platform,
        "-DCMAKE_OSX_ARCHITECTURES=arm64", "-DCMAKE_BUILD_TYPE=Release",
        "-DALSOFT_UTILS=OFF", "-DALSOFT_EXAMPLES=OFF", "-DALSOFT_ENABLE_MODULES=OFF",
        "-DALSOFT_UPDATE_BUILD_VERSION=OFF", "-DALSOFT_EAX=ON",
        "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", "-DALSOFT_BACKEND_OBOE=OFF", "-DALSOFT_BACKEND_OPENSL=OFF",
        "-DALSOFT_REQUIRE_COREAUDIO=ON", "-DHAVE_WFUNCTION_EFFECTS=OFF"], check=True)
    subprocess.run(["cmake", "--build", str(build), "--parallel", "8"], check=True)
    library = build / "libopenal.1.25.2.dylib"
    receipt = {"revision": REVISION, "archive_sha256": archive_pin, "platform": "ios-arm64" if args.ios else "macos-arm64",
               "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest()}
    (build / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
