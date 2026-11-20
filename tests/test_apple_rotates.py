from pathlib import Path
import unittest
from tools import apple_rotates


class AppleRotatePreparationTest(unittest.TestCase):
    def test_preserves_every_byte_except_pinned_rotate_loops(self):
        source = Path(__file__).resolve().parents[1] / "generated/ut3/functions_0261.c"
        original = source.read_bytes()
        candidate, count = apple_rotates.transform(original)
        self.assertEqual(count, 256)
        self.assertEqual(candidate.replace(apple_rotates.DIRECT, apple_rotates.LOOP), original)

    def test_rejects_changed_original_body(self):
        source = Path(__file__).resolve().parents[1] / "generated/ut3/functions_0261.c"
        original = source.read_bytes().replace(b"L_00B4F5F0:", b"L_00B4F5F0: /* altered */", 1)
        with self.assertRaises(ValueError):
            apple_rotates.transform(original)

    def test_unrelated_functions_are_untouched(self):
        source = b"void sub_00000000(void) { return; }\n"
        self.assertEqual(apple_rotates.transform(source), (source, 0))
