"""Prepare the Mach-O build's lifted source list and native overrides."""
import argparse
import json
from pathlib import Path
import re

from lift_build import (
    DEFAULT_WARM_FUNCTIONS, NATIVE_CALL_CONTRACT, ROOT, UE3_NATIVE_TARGETS,
    WRAPS, X87_SLOT_MODULES, generated_sources, host_overrides,
    native_same_unit_calls, sha, validate_native_call_contract,
)
import x87_slots
import apple_rotates


def write_if_changed(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_bytes() != contents:
        path.write_bytes(contents)


WRAPPED_SYMBOL = re.compile(rb"\bsub_(?:" + b"|".join(name[4:].encode() for name in WRAPS) + rb")\b")
WRAPPED_BODY = re.compile(rb"^void (sub_[0-9A-F]{8})\(void\) \{", re.M)
NATIVE_SAME_UNIT = {name.encode() for name in UE3_NATIVE_TARGETS}


def apple_platform_calls(text):
    # The optional file-backed reader must also see these four direct calls
    # beside its generated body. Keep the original body and original key
    # validator intact, and publish the full guest register state via ICALL.
    return text.replace(b"RECOMP_CALL(sub_0120E200)", b"RECOMP_ICALL(0x0120E200u)")


def rename_originals(text):
    """Match ELF wrap behavior and keep the same-unit UE3 overrides."""
    local = {name for name in WRAPPED_BODY.findall(text) if WRAPPED_SYMBOL.fullmatch(name)}
    if not local:
        return text

    def reference(match):
        name = match[0]
        return b"__real_" + name if name in local and name not in NATIVE_SAME_UNIT else name

    text = WRAPPED_SYMBOL.sub(reference, text)
    # UE3 native sites were redirected by the shared rewrite or will use the
    # public linker alias. Their body is still available through __real_*.
    text = WRAPPED_BODY.sub(
        lambda match: b"void __real_" + match[1] + b"(void) {" if match[1] in local else match[0],
        text,
    )
    declares = b"".join(b"extern void __real_" + name + b"(void);\n" for name in sorted(local))
    return declares + text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--protocol", type=Path)
    parser.add_argument("--x87-locals", type=Path)
    parser.add_argument("--host-source", type=Path, action="append", default=[])
    parser.add_argument("--sha1-rotates", action="store_true", help="Simplify pinned SHA-1 rotates without changing guest instructions or flags")
    args = parser.parse_args()
    if args.x87_locals and not args.protocol:
        parser.error("--x87-locals requires --protocol")

    generated = args.generated.resolve()
    specs = json.loads((ROOT / "config/modules.json").read_text())["modules"]
    modules = set(re.findall(r'^\s*\{\s*"([^"]+)"', (generated / "modules.inc").read_text(), re.M))
    missing = {spec["file"] for spec in specs} - modules
    if missing:
        parser.error("complete lift required; missing: " + ", ".join(sorted(missing)))
    lifted, pinned = generated_sources(generated)
    protocol = locals_plan = None
    if args.protocol:
        from protocol_transform import Protocol, apply_protocol
        full = (set(WRAPS) | host_overrides(args.host_source)) - NATIVE_CALL_CONTRACT
        warm = set(DEFAULT_WARM_FUNCTIONS.read_text().split())
        protocol = Protocol(args.protocol, full=full, warm=warm, masked_native=NATIVE_CALL_CONTRACT)
        validate_native_call_contract(protocol)
        if args.x87_locals:
            import x87_locals
            locals_plan = x87_locals.Plan(args.x87_locals)
        pinned[args.protocol] = sha(args.protocol)
        if args.x87_locals:
            pinned[args.x87_locals] = sha(args.x87_locals)

    output = args.output.resolve()
    output_sources = []
    for source in lifted:
        original = source.read_bytes()
        transformed = original
        if source != generated / "dispatch.c":
            module = source.parent.name
            if module in X87_SLOT_MODULES:
                transformed = x87_slots.transform_file(transformed.decode(), module)[0].encode()
            if module == "ut3":
                transformed = native_same_unit_calls(transformed.decode())[0].encode()
                transformed = apple_platform_calls(transformed)
                if args.sha1_rotates:
                    transformed = apple_rotates.transform(transformed)[0]
            if protocol:
                transformed = apply_protocol(transformed, protocol, module)
            if locals_plan is not None:
                transformed = x87_locals.apply_x87(transformed, locals_plan)
            transformed = rename_originals(transformed)
            if transformed != original:
                include = b'#include "' + module.encode() + b'/functions.h"'
                transformed = transformed.replace(b'#include "functions.h"', include, 1)
        if transformed != original:
            target = output / "sources" / source.relative_to(generated)
            write_if_changed(target, transformed)
            output_sources.append(target)
        else:
            output_sources.append(source)

    cmake = ["set(UT3_LIFTED_SOURCES", *(f'  "{path.as_posix()}"' for path in output_sources), ")"]
    cmake += ["set(UT3_WRAPS", *(f"  {name}" for name in WRAPS), ")"]
    cmake += ["set(UT3_LIFT_INPUTS", *(f'  "{path.as_posix()}"' for path in [*lifted, *pinned]), ")"]
    write_if_changed(output / "lifted.cmake", ("\n".join(cmake) + "\n").encode())
    receipt = {"files": {path.as_posix(): digest for path, digest in sorted(pinned.items())},
               "source_count": len(output_sources), "masked_protocol": bool(protocol),
               "local_x87_plan": bool(locals_plan), "sha1_direct_rotates": args.sha1_rotates,
               "sha1_rotate_overlay_sha256": sha(ROOT / "tools/apple_rotates.py") if args.sha1_rotates else None}
    write_if_changed(output / "lift-receipt.json", (json.dumps(receipt, indent=2) + "\n").encode())
    print(f"Prepared {len(output_sources)} lifted sources and {len(WRAPS)} Mach-O wrappers.")


if __name__ == "__main__":
    main()
