"""Cross-compile the pinned native DXVK and Metal WSI for physical iOS ARM64."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from build_dxvk_macos import apply_apple
from d3d9_portability import apply_d3d9_portability
from d3d9_profiling import apply_pipeline_profiling
from dxvk_source import ROOT, REVISION, prepare_source, run, sha, write


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, required=True, help="Pinned macOS Vulkan SDK containing host shader tools")
    parser.add_argument("--meson", type=Path, required=True)
    parser.add_argument("--build", type=Path, default=ROOT / "build/apple/phase6/dxvk")
    parser.add_argument("--profile-pipelines", action="store_true", help="Instrument pipeline API duration when UT3_PIPELINE_TRACE=1")
    args = parser.parse_args()
    build = args.build.resolve()
    source = build.with_name(build.name + "-source")
    pins = json.loads((ROOT / "dependencies-dxvk.json").read_text())
    prepare_source(pins, args.source.resolve(), source, platform="apple")
    apply_apple(source)
    apply_d3d9_portability(source)
    if args.profile_pipelines:
        apply_pipeline_profiling(source)
    sysroot = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    compiler_flags = ["-target", "arm64-apple-ios18.0", "-isysroot", sysroot]
    cross = build.parent / "ios-arm64.ini"
    write(cross, f"""[binaries]
c = ['/usr/bin/xcrun', '--sdk', 'iphoneos', 'clang']
cpp = ['/usr/bin/xcrun', '--sdk', 'iphoneos', 'clang++']
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
[properties]
needs_exe_wrapper = true
[built-in options]
c_args = {compiler_flags!r}
cpp_args = {compiler_flags!r}
c_link_args = {compiler_flags!r}
cpp_link_args = {compiler_flags!r}
""")
    env = dict(os.environ)
    env["PATH"] = str(args.sdk.resolve() / "bin") + os.pathsep + env["PATH"]
    env["GIT_CEILING_DIRECTORIES"] = str(source.parent)
    if not (build / "build.ninja").exists():
        run([args.meson.resolve(), "setup", build, source, "--cross-file", cross,
             "--buildtype=release", "-Denable_dxgi=false", "-Denable_d3d10=false",
             "-Denable_d3d11=false", "-Denable_d3d8=false", "-Denable_d3d9=true"], env=env)
    run(["ninja", "-C", build, "-j", "4"], env=env)
    library = build / "src/d3d9/libdxvk_d3d9.dylib"
    write(build / "receipt.json", json.dumps({"upstream": REVISION, "platform": "ios-arm64",
          "library_sha256": sha(library), "sysroot": sysroot,
          "compatibility": "explicit-d3d9-bounds-and-typed-read-only-dummies",
          "pipeline_profiling": args.profile_pipelines,
          "profiling_overlay_sha256": sha(ROOT / "tools/d3d9_profiling.py") if args.profile_pipelines else None,
          "portability_overlay_sha256": {
              name: sha(ROOT / name) for name in (
                  "tools/d3d9_portability.py", "platform/apple/ios/d3d9_unbound.inc")
          }}, indent=2) + "\n")


if __name__ == "__main__":
    main()
