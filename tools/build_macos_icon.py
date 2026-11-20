"""Convert the supplied PNG to a macOS ICNS file with PNG-backed representations."""
import argparse
from pathlib import Path
import struct
import subprocess
from tempfile import TemporaryDirectory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png", type=Path)
    parser.add_argument("icns", type=Path)
    args = parser.parse_args()
    args.icns.parent.mkdir(parents=True, exist_ok=True)

    # ICNS big-endian lengths include their eight-byte type and length header.
    sizes = ((b"icp4", 16), (b"icp5", 32), (b"icp6", 64),
             (b"ic07", 128), (b"ic08", 256), (b"ic09", 512), (b"ic10", 1024))
    chunks = []
    with TemporaryDirectory(dir=args.icns.parent) as work:
        for kind, size in sizes:
            png = Path(work) / f"icon-{size}.png"
            subprocess.run(["/usr/bin/sips", "-z", str(size), str(size), args.png,
                            "--out", png], check=True, stdout=subprocess.DEVNULL)
            data = png.read_bytes()
            chunks.append(struct.pack(">4sI", kind, len(data) + 8) + data)
    payload = b"".join(chunks)
    args.icns.write_bytes(struct.pack(">4sI", b"icns", len(payload) + 8) + payload)


if __name__ == "__main__":
    main()
