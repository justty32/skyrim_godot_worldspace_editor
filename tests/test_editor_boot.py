#!/usr/bin/env python3
"""Root-scene boot contract: what res://main.tscn actually assembles, in the real Godot runtime.

`WorldspaceEditor._ready` builds the entire editor — terrain, camera rig, cursor, grid outlines,
four tool nodes and a side panel stitched together from four separate UI modules. None of that is
covered by the parse gate, which only proves the files compile. This boots the scene headless so a
dropped or re-ordered wiring line fails here instead of in front of a human with the GUI open.
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
PROBE_SCRIPT = "res://tests/editor_boot_contract.gd"
# main.gd's defaults. Vertex grid is cells×32+1 per axis; grid outlines are (cx+1)+(cy+1) meshes.
CELLS = [3, 2]
VERTS = [3 * 32 + 1, 2 * 32 + 1]
HEIGHT_RANGE = [4000.0, 4500.0]
GRID_LINES = (3 + 1) + (2 + 1)
GROWN_CELLS = [4, 3]
GROWN_VERTS = [4 * 32 + 1, 3 * 32 + 1]
GROWN_GRID_LINES = (4 + 1) + (3 + 1)
# Three collapsible sections; GridUi appends a plain bold "GRID (CELLS)" block instead of one.
EXPECTED_SECTIONS = ["HEIGHT (TERRAIN)", "OBJECT (PLACEMENT)", "TEXTURE (SPLAT)"]


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


class EditorBootContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the boot contract")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="editor_boot_contract_")
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

    def test_scene_builds_terrain_camera_and_every_tool_node(self) -> None:
        self.assertEqual(CELLS, self.result["cells"])
        self.assertEqual(VERTS, self.result["verts"])
        self.assertEqual(HEIGHT_RANGE, self.result["height_range"])
        self.assertTrue(self.result["has_camera"])
        for name, present in self.result["tools_in_tree"].items():
            self.assertTrue(present, f"{name} is missing from the scene tree")
        self.assertTrue(self.result["cursor_present"])
        self.assertTrue(self.result["cursor_hidden_at_boot"])
        self.assertEqual(GRID_LINES, self.result["grid_lines"])

    def test_side_panel_carries_every_module_section(self) -> None:
        # The panel is assembled from four separate modules (WorldUI, PlacementUi, SplatUi, GridUi);
        # each appends one collapsible section, and the two status labels come back from WorldUI.
        self.assertEqual(EXPECTED_SECTIONS, self.result["panel_sections"])
        self.assertTrue(self.result["labels_wired"])

    def test_splat_starts_with_one_layer_over_the_base_ground(self) -> None:
        self.assertEqual(1, self.result["splat_layers"])
        self.assertEqual(0, self.result["splat_active"])
        self.assertEqual("Skyrim.esm:0x000C14", self.result["splat_base_texture"])

    def test_place_and_splat_modes_are_mutually_exclusive(self) -> None:
        self.assertEqual([False, False, False], self.result["modes_at_boot"])
        # [place, splat, painting] — turning one mode on clears the other AND drops the stroke.
        self.assertEqual([True, False, False], self.result["after_place_on"])
        self.assertEqual([False, True, False], self.result["after_splat_on"])

    def test_growing_the_worldspace_keeps_splat_aligned_with_the_heightmap(self) -> None:
        grown = self.result["after_grow"]
        self.assertEqual(GROWN_CELLS, grown["cells"])
        self.assertEqual(GROWN_VERTS, grown["verts"])
        self.assertEqual(GROWN_VERTS[0] * GROWN_VERTS[1], grown["splat_alpha_size"])
        self.assertEqual(GROWN_GRID_LINES, grown["grid_lines"])
        # GridUi's readout is driven by terrain_changed, so this also proves that hook survived.
        self.assertEqual(
            "%d×%d cells  (%d×%d verts)" % (*GROWN_CELLS, *GROWN_VERTS),
            grown["grid_dims_label"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
