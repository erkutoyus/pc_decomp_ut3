"""Preserve the pinned SHA-1 guest body while simplifying its 32-bit rotates."""
import argparse
import hashlib
from pathlib import Path
import re

BODY = re.compile(rb"^void sub_00B4F5F0\(void\) \{.*?^\}", re.M | re.S)
PIN = "54a7e266b8df20596350072832545082f58dbef05c0bafdde4f2378ef077c1e5"
LOOP = b"for (uint32_t _i=0;_i<_rn;_i++){ uint32_t _rb = (_rv >> 31) & 1u; _rv = ((_rv << 1) | _rb) & 0xFFFFFFFFu; _cf = _rb; }"
DIRECT = b"if (_rn) { _rv = (_rv << _rn) | (_rv >> (32u - _rn)); _cf = _rv & 1u; }"


def transform(text):
    match = BODY.search(text)
    if not match:
        return text, 0
    body = match[0]
    if hashlib.sha256(body).hexdigest() != PIN or body.count(LOOP) != 256:
        raise ValueError("unexpected pinned SHA-1 body; do not simplify unreviewed guest code")
    # Existing count masking guarantees 0..31. The guard preserves the old CF
    # for zero and prevents a shift by 32. The following generated flag code
    # is unchanged. Keep every guest load/store, register and return intact.
    body = body.replace(LOOP, DIRECT)
    return text[:match.start()] + body + text[match.end():], 256


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    original = args.source.read_bytes()
    optimized, count = transform(original)
    if count != 256:
        parser.error("fixture requires the pinned SHA-1 function")
    reference = BODY.search(original)[0].replace(b"void sub_00B4F5F0", b"void sha1_reference", 1)
    candidate = BODY.search(optimized)[0].replace(b"void sub_00B4F5F0", b"void sha1_candidate", 1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(reference + b"\n" + candidate + b"\n")


if __name__ == "__main__":
    main()
