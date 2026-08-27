#!/usr/bin/env python3
"""Splat-layer contracts (splatmap PNG + layer state), executed by the real Godot runtime.

The splatmap PNG is a producer contract: ModForge reads it as `textureLayers[].splatmap` and turns
it into ATXT/VTXT alpha, so its row convention and its dimensions have to be exactly the vertex
grid, north on top. The Y-flip is checked against a PNG decoded here in Python, not against Godot's
own reader, so a writer and reader that agree on the WRONG convention cannot both pass.

Also pins two side-panel behaviours that only show up while a brush is held down, because
`SplatTool.paint()` emits `changed` on every tick.
"""

from __future__ import annotations

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
PROBE_SCRIPT = "res://tests/splat_contract.gd"
QUANTISATION = 1.0 / 255.0 + 1e-6      # the PNG is 8-bit; a round trip may lose that much
CHANNELS_FOR_COLOR_TYPE = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


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


def decode_png_first_channel(path: Path) -> tuple[int, int, list[list[int]]]:
    """Minimal 8-bit PNG decoder → rows of channel-0 samples, top row first."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    offset = 8
    header: tuple[int, ...] = ()
    idat = bytearray()
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        payload = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
        offset += 12 + length

    width, height, depth, color_type, _compression, _filter, interlace = header
    assert depth == 8, f"expected 8-bit samples, got {depth}"
    assert interlace == 0, "interlaced PNG is not part of the splatmap contract"
    channels = CHANNELS_FOR_COLOR_TYPE[color_type]
    stride = width * channels

    raw = zlib.decompress(bytes(idat))
    rows: list[list[int]] = []
    prior = bytearray(stride)
    pos = 0
    for _ in range(height):
        filter_type = raw[pos]
        current = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        for index in range(stride):
            left = current[index - channels] if index >= channels else 0
            above = prior[index]
            upper_left = prior[index - channels] if index >= channels else 0
            predictor = (
                0, left, above, (left + above) // 2, paeth(left, above, upper_left)
            )[filter_type]
            current[index] = (current[index] + predictor) & 0xFF
        rows.append([current[column * channels] for column in range(width)])
        prior = current
    return width, height, rows


class SplatContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the splat contract")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="splat_contract_")
        work = Path(cls.tempdir.name)
        project = work / "godot"
        shutil.copytree(GODOT_PROJECT, project, ignore=shutil.ignore_patterns(".godot"))
        cls.png_path = work / "splat.png"
        result_path = work / "result.json"

        run([cls.godot, "--editor", "--headless", "--path", str(project), "--quit"], REPO)
        run(
            [cls.godot, "--headless", "--path", str(project), "--script", PROBE_SCRIPT,
             "--", str(cls.png_path), str(result_path)],
            REPO,
        )
        cls.result = json.loads(result_path.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def test_splatmap_png_is_the_vertex_grid_with_north_on_top(self) -> None:
        self.assertTrue(self.result["saved"])
        verts_x = self.result["verts_x"]
        verts_y = self.result["verts_y"]
        width, height, rows = decode_png_first_channel(self.png_path)
        self.assertEqual((verts_x, verts_y), (width, height))

        written = self.result["written"]
        # PNG row 0 is the TOP row and must hold the NORTHERNMOST grid row (world row verts_y-1);
        # the last PNG row holds world row 0. Getting this backwards flips every exported layer.
        self.assertEqual(round(written["nw"] * 255), rows[0][0])
        self.assertEqual(round(written["sw"] * 255), rows[height - 1][0])
        mid_png_row = (verts_y - 1) - self.result["mid_row"]
        self.assertEqual(round(written["mid"] * 255), rows[mid_png_row][self.result["mid_col"]])

    def test_alpha_survives_the_png_round_trip(self) -> None:
        written = self.result["written"]
        trip = self.result["round_trip"]
        self.assertEqual(self.result["verts_x"] * self.result["verts_y"], trip["size"])
        for corner in ("sw", "nw", "mid"):
            self.assertAlmostEqual(written[corner], trip[corner], delta=QUANTISATION)
        self.assertAlmostEqual(0.0, trip["blank"], delta=QUANTISATION)

    def test_a_wrongly_sized_png_is_refused(self) -> None:
        self.assertTrue(self.result["mismatch_returns_empty"])

    def test_set_active_survives_an_empty_layer_set(self) -> None:
        # clampi(i, 0, -1) returns -1, and layers[-1] is the LAST element in GDScript — on an empty
        # array that throws. Nothing removes layers today; this keeps that door shut.
        self.assertEqual(0, self.result["empty_layers"]["active"])
        self.assertEqual("", self.result["empty_layers"]["texture"])

    def test_layer_controls_do_not_thrash_while_painting(self) -> None:
        sync = self.result["ui_sync"]
        idle = sync["idle"]
        self.assertEqual(1, sync["initial_items"])
        # Repeated syncs with nothing changed must leave the dropdown untouched...
        self.assertEqual(1, idle["items"])
        self.assertEqual(0, idle["selected"])
        self.assertTrue(idle["metadata_kept"], "the OptionButton was rebuilt with no state change")
        # ...but a real layer addition still rebuilds and re-selects it.
        self.assertEqual(2, sync["after_add"]["items"])
        self.assertEqual(1, sync["after_add"]["selected"])
        self.assertFalse(sync["after_add"]["metadata_kept"])
        self.assertEqual(sync["added_layer"], sync["after_add"]["text"])

    def test_a_half_typed_ltex_ref_is_not_wiped_by_painting(self) -> None:
        sync = self.result["ui_sync"]
        self.assertTrue(sync["focus_actually_taken"], "probe never got focus; the guard is untested")
        self.assertEqual(sync["half_typed"], sync["while_typing"])
        self.assertEqual(sync["added_layer"], sync["after_release"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
