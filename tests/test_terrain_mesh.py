#!/usr/bin/env python3
"""Height-brush and incremental-mesh contracts, executed by the real Godot runtime.

The heightmap is this editor's primary output — ModForge turns it into LAND/VHGT — and every brush
tick reaches it through `TerrainBrush.apply` + `TerrainMeshBuilder.update_region`. The incremental
path exists purely because it is supposed to produce the same mesh as a full rebuild; that claim
was written in a comment and never checked.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GODOT_PROJECT = REPO / "godot"
PROBE_SCRIPT = "res://tests/terrain_mesh_contract.gd"
STROKES = ("raise_middle", "raise_corner", "lower_middle", "flatten_middle", "smooth_middle")
MESH_ARRAYS = ("verts", "normals", "uvs", "colors", "indices")
BRUSH_RADIUS = 4.0
MAX_HEIGHT = 4500.0


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


class TerrainMeshContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the terrain mesh contract")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="terrain_mesh_contract_")
        work = Path(cls.tempdir.name)
        project = work / "godot"
        shutil.copytree(GODOT_PROJECT, project, ignore=shutil.ignore_patterns(".godot"))
        result_path = work / "result.json"

        run([cls.godot, "--editor", "--headless", "--path", str(project), "--quit"], REPO)
        run(
            [cls.godot, "--headless", "--path", str(project), "--script", PROBE_SCRIPT,
             "--", str(result_path)],
            REPO,
        )
        cls.result = json.loads(result_path.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def test_an_incremental_stroke_matches_a_full_rebuild(self) -> None:
        # A stroke edits a box of vertices, but their normals read one vertex further out — so the
        # recomputed normal box has to be the vertex box expanded by 1. An off-by-one here leaves a
        # stale lighting seam around every brush stroke that only a full rebuild washes away.
        for stroke in STROKES:
            with self.subTest(stroke=stroke):
                mismatches = self.result[stroke]
                self.assertEqual(sorted(MESH_ARRAYS), sorted(mismatches))
                for array, bad in mismatches.items():
                    self.assertEqual(
                        0, bad,
                        f"{stroke}: {array} differs from a full rebuild"
                        + (" (array length changed)" if bad == -1 else f" in {bad} element(s)"),
                    )

    def test_raise_falls_off_to_nothing_at_the_brush_radius(self) -> None:
        profile = self.result["raise_profile"]
        self.assertGreater(profile["centre_gain"], 0.0)
        # smoothstep falloff: strongest at the centre, weaker halfway out, zero at the radius.
        self.assertGreater(profile["centre_gain"], profile["mid_gain"])
        self.assertGreater(profile["mid_gain"], 0.0)
        self.assertEqual(0.0, profile["edge_gain"], "a vertex exactly at the radius must not move")
        self.assertEqual(0, profile["outside_touched"], "the brush reached past its own radius")
        self.assertGreater(profile["inside_raised"], 0)

    def test_a_long_stroke_saturates_instead_of_leaving_the_height_range(self) -> None:
        # Heights outside [min_height, max_height] would encode into VHGT as garbage downstream.
        clamping = self.result["clamping"]
        self.assertEqual(0, clamping["over_max"])
        self.assertEqual(0, clamping["under_min"])
        self.assertEqual(MAX_HEIGHT, clamping["centre"], "200 raise ticks should reach the ceiling")


if __name__ == "__main__":
    unittest.main(verbosity=2)
