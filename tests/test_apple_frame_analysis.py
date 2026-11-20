import tempfile
import unittest
from pathlib import Path
from tools.analyze_apple_frames import read_frames, summarize


class FrameAnalysisTest(unittest.TestCase):
    def read(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frames.csv"
            path.write_text(content)
            return read_frames(path)

    def test_hitch_is_included_in_distribution(self):
        rows = self.read("frame,elapsed_ms,gap_ms\n2,16,16\n3,32,16\n4,232,200\n")
        result = summarize(rows)
        self.assertEqual(result["over_100_ms"], 1)
        self.assertEqual(result["max_ms"], 200)
        self.assertAlmostEqual(result["fps_from_intervals"], 3000 / 232)
        self.assertEqual(result["p50_ms"], 16)

    def test_windows_use_interval_end_without_discarding_stall(self):
        rows = [(2, 16, 16), (3, 1200, 1184), (4, 1216, 16)]
        self.assertEqual(summarize(rows, 1, 2)["max_ms"], 1184)
        self.assertEqual(summarize(rows, 2, 3), {"intervals": 0})

    def test_rejects_incomplete_or_invalid_trace(self):
        for content in ("frame,elapsed_ms,gap_ms\n2,nan,16\n", "frame,elapsed_ms,gap_ms\n2,16,0\n",
                        "frame,elapsed_ms,gap_ms\n2,16,16\n3,40,16\n",
                        "frame,elapsed_ms,gap_ms\n2,16,16\n2,32,16\n"):
            with self.subTest(content=content), self.assertRaises(ValueError):
                self.read(content)
