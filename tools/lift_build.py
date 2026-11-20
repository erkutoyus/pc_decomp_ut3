"""Shared inputs and transformations for statically lifted UT3 builds."""
import hashlib
import json
from pathlib import Path
import re

# Lifted modules whose functions keep their x87 stack in C locals (tools/x87_slots.py): the game's own
# scalar float code, PhysXCore (its CPU solver carries the PhysX Mod Pack maps), the PhysX cooking and
# character libraries, and Bink, Vorbis and the resampler. A function with another x87 interface keeps
# the global window; so do the CRT's math helpers (msvcr80), whose interfaces are x87 values.
X87_SLOT_MODULES = ("ut3", "physxcore", "nxcooking", "nxcharacter", "binkw32", "vorbis", "libresample")

UE3_NATIVE_TARGETS = [
    "sub_00486030", "sub_0117C3B0",  # UE3 matrix products and sphere culling
    "sub_0117D890",  # Light/primitive sphere rejection; other cases keep the lifted predicate
    "sub_006044F0", "sub_00B65BD0", "sub_00BF8120",  # Actor transforms and tick containers
    "sub_01178E50", "sub_01178EA0",  # Per-view primitive lookup
    "sub_00F058D0", "sub_0088B010",  # Draw traversal and actor iterator
    "sub_00F05700", "sub_00F05AA0", "sub_00EFE060", "sub_00EFE230",  # The same draw traversal, other draw lists
    "sub_00F05530",  # The 16-byte draw-list traversal with the sparse array at +0x28
    "sub_00F01CF0",  # Connected primitive and light visibility traversal
    "sub_005DAF50",  # Sparse allocation-bit iterator initialization
    "sub_00BF81A0", "sub_00BF82A0", "sub_00BF82F0", "sub_00BF8340",  # Visibility bit-array storage
    "sub_00EFF830",  # Per-view light-array reset
    "sub_0117AEC0", "sub_01178C60",  # Temporal occlusion decision and bounds preparation
    "sub_010275E0",  # AI navigation graph search
    "sub_006A97C0", "sub_00EA3C60", "sub_01079C10", "sub_01079F80",  # ReachSpec support/cost and edge lookup
    "sub_00FC8DE0", "sub_00FCBCB0",  # AI perception eligibility and controller traversal
    "sub_01156630",  # Segment/AABB query used by perception and movement traces
    "sub_004B49A0",  # TMap<FName, V>::Find (core_native.c; 00B65BD0 is its TMap<int, V> sibling)
    "sub_004B9D60", "sub_00F78830", "sub_00E2DC90",  # TMap finds with object and two-word keys (core_native.c)
    "sub_00BC1310", "sub_00BC12C0",  # The script VM's instance and local variable opcodes (core_native.c)
    "sub_00EC2580", "sub_00EC2610", "sub_00EC26A0", "sub_00EC2730",  # Shader parameter descriptor bridges
    "sub_0116C250",  # Segment/box slab test of collision checks (collision_native.c)
    "sub_00BF8DA0",  # Baked distribution lookup for particles (particle_native.c)
    "sub_01590CF0",  # D3D9 RHI query wait: poll before reading the clock (query_native.c)
]
WRAPS = [
    "sub_00F75DB0", "sub_00486270", "sub_00C85710", "sub_00C12290", "sub_00B6AF10", "sub_010FC820",
    "sub_1E23D3A0", "sub_1E23A700", "sub_1E23D300", "sub_1E213B70",  # PhysX collision/pair kernels
] + UE3_NATIVE_TARGETS
# These native entries preserve the lifted summary's caller-visible contract (0x17, flags dead).
NATIVE_CALL_CONTRACT = {"sub_00EC2580", "sub_00EC2610", "sub_00EC26A0", "sub_00EC2730", "sub_0117D890"}

ROOT = Path(__file__).resolve().parents[1]
# The inputs of the three optimisations of the lifted code that are on by default (see apply_protocol_defaults):
# a tools/call_protocol.py summary and a tools/x87_locals.py plan (both made on first use, about 15 minutes, from
# the same PE images and generated sources the build compiles) and the list of the bodies a WAR-Torlan match runs.
DEFAULT_CALL_PROTOCOL = ROOT / "build/call-protocol-v2/summary.json"
DEFAULT_X87_LOCALS = ROOT / "build/call-protocol-v2/x87-v3.json"
DEFAULT_WARM_FUNCTIONS = ROOT / "config/warm-functions.txt"
# Host translation units built with the generated code's separated guest-state profile
# (engine/runtime/guest_state_prefix.h): they work on the global guest registers and guest memory only
# through the runtime macros and define no identifiers named like the register aliases.
SEPARATED_HOST_SOURCES = (
    "render_visibility_native.c", "game_native.c", "render_native.c", "render_hash_native.c",
    "render_draw_native.c", "ai_native.c", "ai_reach_native.c", "ai_trace_native.c", "core_native.c",
    "collision_native.c", "crt_native.c", "particle_native.c",
)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


DISPATCH_ADD = re.compile(r'void_dispatch_add\(\s*([A-Za-z_][A-Za-z0-9_]*|0x[0-9A-Fa-f]+)u?\s*,')
NAMED_VA = r'(?:#define\s+{0}\s+|\b{0}\s*=\s*)(0x[0-9A-Fa-f]+)u?\b'


def host_overrides(host_sources):
    """Guest VAs the host replaces through void_dispatch_add, as lifted names.

    Callers of these bodies keep the full call protocol: the host replacement may read any register."""
    names = set()
    for source in host_sources:
        text = source.read_text(encoding="utf-8", errors="replace")
        for token in DISPATCH_ADD.findall(text):
            if token.startswith("0x"):
                names.add("sub_%08X" % int(token, 16))
                continue
            if token in ("va", "old"):
                continue   # core.c's own registration helpers
            match = re.search(NAMED_VA.format(re.escape(token)), text)
            if not match:
                raise ValueError(f"{source.name}: cannot resolve the address of void_dispatch_add({token}, ...)")
            names.add("sub_%08X" % int(match[1], 16))
    return names


def native_same_unit_calls(text):
    # --wrap only redirects undefined symbols; a call beside its definition can be bound or inlined first.
    defined = set(re.findall(r'^void (sub_[0-9A-F]{8})\(void\) \{', text, re.M))
    local = [name for name in UE3_NATIVE_TARGETS if name in defined]
    if not local:
        return text, 0
    called = set()
    def redirect(match):
        called.add(match[1])
        return 'RECOMP_CALL(__wrap_' + match[1] + ')'
    rewritten, count = re.subn(r'\bRECOMP_CALL\((' + '|'.join(local) + r')\)', redirect, text)
    if not count:
        return text, 0
    declarations = ''.join('extern void __wrap_' + name + '(void);\n' for name in sorted(called))
    return declarations + rewritten.replace('#include "functions.h"', '#include "ut3/functions.h"', 1), count


def validate_native_call_contract(protocol):
    for name in NATIVE_CALL_CONTRACT:
        if protocol.call_masks(name) != (0x17, 0x17, 0) or name in protocol.flags_out:
            raise ValueError("Native call contract differs from the proven summary: " + name)


def generated_sources(folder):
    if folder == ROOT / "build/host-smoke":
        return [folder / "dispatch.c"], {}
    specs = json.loads((ROOT / "config/modules.json").read_text())["modules"]
    included = re.findall(r'^\s*\{\s*"([^"]+)"', (folder / "modules.inc").read_text(), re.M)
    by_file = {row["file"]: row for row in specs}
    if not included or len(set(included)) != len(included) or set(included) - by_file.keys():
        raise ValueError("Generated module list is empty, duplicated or unknown")
    if not any(by_file[name].get("exe") for name in included):
        raise ValueError("Generated module list has no executable")
    sources, pinned = [folder / "dispatch.c"], {}
    for name in included:
        spec = by_file[name]
        directory = folder / spec["name"]
        report_path = directory / "report.json"
        report = json.loads(report_path.read_text())
        if report.get("status") != "GENERATED":
            raise ValueError(f"Static generation is incomplete: {name}")
        image = folder / "input" / spec["file"]
        if sha(image) != report.get("image_sha256") or report.get("original_sha256") != spec["sha256"]:
            raise ValueError(f"Generated input hash differs from its report: {name}")
        pinned[image] = sha(image)
        pinned[report_path] = sha(report_path)
        for relative in report["sources"]:
            source = (directory / relative).resolve()
            if source.parent != directory or source.suffix != ".c" or not source.is_file():
                raise ValueError(f"Invalid generated source: {relative}")
            sources.append(source)
    pinned[folder / "modules.inc"] = sha(folder / "modules.inc")
    pinned[folder / "dispatch.c"] = sha(folder / "dispatch.c")
    return sources, pinned




def host_sources():
    """Handwritten shared runtime sources; platform adapters are selected separately."""
    return sorted((ROOT / "engine/host").glob("*.c"), key=lambda source: source.name)
