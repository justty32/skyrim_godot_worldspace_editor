#!/usr/bin/env python3
"""Terrain picking (cursor / click raycast) contracts, executed by the real Godot runtime.

`TerrainCoords.raycast_surface` decides where every editor mode acts: the yellow cursor ring, the
height brush, splat painting and object placement all take its result, and `Vector3.ZERO` is the
agreed "no hit" sentinel. The assertions live here rather than in a Python reimplementation — the
probe calls the production function on a real `TerrainGrid`.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GODOT_PROJECT = REPO / "godot"
PROBE_SCRIPT = "res://tests/terrain_coords_contract.gd"
PROBE_Z = -10.0
INSIDE_X = 10.0
SIDE_ENTRY_Y = 30.0
ZERO = [0.0, 0.0, 0.0]


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


class TerrainCoordsContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the picking contract")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="terrain_coords_contract_")
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

    def assert_close(self, actual: list[float], expected: list[float], tol: float) -> None:
        self.assertEqual(3, len(actual))
        for axis, (got, want) in enumerate(zip(actual, expected)):
            self.assertTrue(
                math.isclose(got, want, abs_tol=tol),
                f"axis {'xyz'[axis]}: got {got!r}, want {want!r} (±{tol})",
            )

    def test_ray_from_above_lands_on_the_surface(self) -> None:
        surface_y = self.result["flat_surface_y"]
        self.assert_close(self.result["down_from_above"], [INSIDE_X, surface_y, PROBE_Z], 0.01)

    def test_misses_report_the_zero_sentinel(self) -> None:
        # A ray that never enters the footprint, and a ray whose ORIGIN is inside the footprint but
        # already underground, are both "no hit" — every caller keys off Vector3.ZERO for that.
        self.assertEqual(ZERO, self.result["outside_footprint"])
        self.assertEqual(ZERO, self.result["origin_under_surface"])

    def test_side_entry_below_the_surface_hits_the_entry_point(self) -> None:
        # Regression: the first march sample is the FOOTPRINT ENTRY, not the ray origin. Treating
        # "first sample is underground" as "the camera is underground" made a low-angle ray at a
        # raised edge report a miss, so the cursor disappeared and clicks were swallowed.
        hit = self.result["side_entry_below_surface"]
        self.assertNotEqual(ZERO, hit)
        self.assert_close(hit, [0.0, SIDE_ENTRY_Y, PROBE_Z], 0.01)

    def test_raised_ground_blocks_a_ray_crossing_the_flat_part(self) -> None:
        hit = self.result["ridge_hit"]
        self.assertNotEqual(ZERO, hit)
        # The ray is horizontal, so it can only be stopped at its own height, on the ridge's near
        # face — i.e. inside the one vertex span where the interpolated ground rises past it.
        self.assertLess(self.result["ridge_x_lo"], hit[0])
        self.assertLess(hit[0], self.result["ridge_x_hi"])
        self.assert_close(hit, [hit[0], self.result["ridge_ray_y"], PROBE_Z], 0.01)


if __name__ == "__main__":
    unittest.main(verbosity=2)
