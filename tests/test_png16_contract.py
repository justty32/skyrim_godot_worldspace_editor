#!/usr/bin/env python3
"""16-bit heightmap PNG contracts, executed by the real Godot runtime."""

from __future__ import annotations

import binascii
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib


REPO = Path(__file__).resolve().parents[1]
GODOT_PROJECT = REPO / "godot"
PROBE_SCRIPT = "res://tests/png16_contract.gd"
ROUNDTRIP_WIDTH = 5
ROUNDTRIP_HEIGHT = 2
ROUNDTRIP_SAMPLES = [0, 1, 255, 256, 257, 32767, 32768, 4660, 65534, 65535]
FILTER_WIDTH = 5
FILTER_ROWS = (
    (0x0000, 0x00FF, 0x0100, 0x1234, 0xFFFF),
    (0x1357, 0x2468, 0x369C, 0x48AD, 0x5ABE),
    (0xFFFF, 0x8000, 0x7FFF, 0x0102, 0xFEFD),
    (0x1111, 0x2222, 0x3333, 0x4444, 0x5555),
    (0xABCD, 0x0001, 0xCDEF, 0x1010, 0xF00D),
)


def executable_from_env_or_path(env_name: str, names: tuple[str, ...]) -> str | None:
    configured = os.environ.get(env_name)
    if configured:
        candidate = Path(configured).expanduser()
        return str(candidate.resolve()) if candidate.is_file() else None
    return next((found for name in names if (found := shutil.which(name))), None)


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    if result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
    if distances[0] <= distances[1] and distances[0] <= distances[2]:
        return left
    return above if distances[1] <= distances[2] else upper_left


def png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


def write_five_filter_png(path: Path) -> None:
    unfiltered_rows = [b"".join(struct.pack(">H", sample) for sample in row) for row in FILTER_ROWS]
    scanlines = bytearray()
    for row_index, current in enumerate(unfiltered_rows):
        filter_type = row_index
        prior = unfiltered_rows[row_index - 1] if row_index else bytes(len(current))
        filtered = bytearray(len(current))
        for index, value in enumerate(current):
            left = current[index - 2] if index >= 2 else 0
            above = prior[index]
            upper_left = prior[index - 2] if index >= 2 else 0
            predictors = (
                0,
                left,
                above,
                (left + above) // 2,
                paeth(left, above, upper_left),
            )
            filtered[index] = (value - predictors[filter_type]) & 0xFF
        scanlines.append(filter_type)
        scanlines.extend(filtered)

    ihdr = struct.pack(">IIBBBBB", FILTER_WIDTH, len(FILTER_ROWS), 16, 0, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(scanlines)))
        + png_chunk(b"IEND", b"")
    )


class Png16ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the PNG16 contract")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="png16_contract_")
        cls.work = Path(cls.tempdir.name)
        cls.project = cls.work / "godot"
        shutil.copytree(GODOT_PROJECT, cls.project, ignore=shutil.ignore_patterns(".godot"))
        cls.roundtrip_path = cls.work / "roundtrip.png"
        filtered_path = cls.work / "five-filters.png"
        result_path = cls.work / "result.json"
        write_five_filter_png(filtered_path)

        run([cls.godot, "--editor", "--headless", "--path", str(cls.project), "--quit"], REPO)
        run(
            [
                cls.godot,
                "--headless",
                "--path",
                str(cls.project),
                "--script",
                PROBE_SCRIPT,
                "--",
                str(cls.roundtrip_path),
                str(filtered_path),
                str(result_path),
            ],
            REPO,
        )
        cls.result = json.loads(result_path.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def test_16_bit_depth_round_trip_is_pixel_exact(self) -> None:
        png = self.roundtrip_path.read_bytes()
        self.assertEqual(b"\x89PNG\r\n\x1a\n", png[:8])
        self.assertEqual(b"IHDR", png[12:16])
        self.assertEqual((ROUNDTRIP_WIDTH, ROUNDTRIP_HEIGHT), struct.unpack(">II", png[16:24]))
        self.assertEqual((16, 0, 0, 0, 0), tuple(png[24:29]))

        expected_image_order = ROUNDTRIP_SAMPLES[ROUNDTRIP_WIDTH:] + ROUNDTRIP_SAMPLES[:ROUNDTRIP_WIDTH]
        self.assertEqual(expected_image_order, self.result["roundtrip_samples"])
        self.assertEqual(ROUNDTRIP_SAMPLES, self.result["roundtrip_heights"])

    def test_all_five_scanline_filters_decode_pixel_exactly(self) -> None:
        self.assertEqual([0, 1, 2, 3, 4], self.result["filter_types"])
        expected = [sample for row in FILTER_ROWS for sample in row]
        self.assertEqual(expected, self.result["filtered_samples"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
