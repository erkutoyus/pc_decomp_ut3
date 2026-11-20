"""Summarize accepted Vulkan Present intervals (not GPU/display completion times)."""
import argparse
import csv
import json
import math
from pathlib import Path


def read_frames(path):
    rows = []
    with Path(path).open(newline="") as file:
        reader = csv.DictReader(file)
        if reader.fieldnames != ["frame", "elapsed_ms", "gap_ms"]:
            raise ValueError("unexpected frame trace header")
        previous_frame, previous_time = 0, 0.0
        for row in reader:
            frame = int(row["frame"])
            elapsed, gap = float(row["elapsed_ms"]), float(row["gap_ms"])
            if not all(math.isfinite(x) for x in (elapsed, gap)) or gap <= 0 or elapsed <= previous_time or frame <= previous_frame:
                raise ValueError("nonfinite, nonpositive or unordered frame trace")
            if abs((elapsed - previous_time) - gap) > 0.01:
                raise ValueError("trace intervals do not match elapsed time; missing rows or discontinuity")
            rows.append((frame, elapsed, gap))
            previous_frame, previous_time = frame, elapsed
    return rows


def percentile(values, fraction):
    index = (len(values) - 1) * fraction
    lower = math.floor(index)
    upper = math.ceil(index)
    return values[lower] + (values[upper] - values[lower]) * (index - lower)


def summarize(rows, start_s=0, end_s=math.inf):
    # Use each interval's ending timestamp; retain hitches across window edges.
    gaps = sorted(gap for _, elapsed, gap in rows if start_s * 1000 <= elapsed < end_s * 1000)
    if not gaps:
        return {"intervals": 0}
    duration = sum(gaps)
    return {"intervals": len(gaps), "represented_s": duration / 1000,
            "fps_from_intervals": 1000 * len(gaps) / duration,
            "mean_ms": duration / len(gaps), "p50_ms": percentile(gaps, .50),
            "p95_ms": percentile(gaps, .95), "p99_ms": percentile(gaps, .99),
            "max_ms": gaps[-1],
            **{f"over_{threshold}_ms": sum(gap > threshold for gap in gaps) for threshold in (25, 50, 100)}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("--window", action="append", help="name:start_seconds:end_seconds; repeatable")
    args = parser.parse_args()
    rows = read_frames(args.trace)
    windows = args.window or ["initial:0:30", "settling:30:120", "later:120:300"]
    results = {"metric": "accepted Vulkan Present gaps; excludes time before first Present", "whole": summarize(rows), "windows": {}}
    for window in windows:
        name, start, end = window.split(":")
        start, end = float(start), float(end)
        if not math.isfinite(start) or not math.isfinite(end) or not 0 <= start < end:
            parser.error("window must have finite bounds 0 <= start < end")
        results["windows"][name] = summarize(rows, start, end)
    print(json.dumps(results, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
