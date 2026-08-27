#!/usr/bin/env python3
"""Every .gd in the Godot project must parse and type-resolve.

The two contract suites only execute the scripts they need (PlacementsIo / TerrainCoords /
ModelFetch and what those pull in), so a broken sibling — say `tex_fetch.gd`, reachable only
from SplatTool — can slip through both of them green. The headless *editor* scan does not help
either: it prints `SCRIPT ERROR: Parse Error` and still exits 0.

`--check-only --script res://<file>` does exit non-zero, and it resolves the script's external
class members too (a file that references a broken `class_name` fails with it). Sweeping every
.gd with it is the mechanical gate that makes a pure-move refactor verifiable on a machine that
cannot open the GUI.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GODOT_PROJECT = REPO / "godot"


def executable_from_env_or_path(env_name: str, names: tuple[str, ...]) -> str | None:
    configured = os.environ.get(env_name)
    if configured:
        candidate = Path(configured).expanduser()
        return str(candidate.resolve()) if candidate.is_file() else None
    return next((found for name in names if (found := shutil.which(name))), None)


class GdScriptParseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the GDScript parse gate")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="godot_parse_gate_")
        cls.project = Path(cls.tempdir.name) / "godot"
        # Same isolation rule as the other suites: the editor scan writes .gd.uid sidecars and a
        # .godot cache, so it only ever sees a disposable copy of the checkout.
        shutil.copytree(GODOT_PROJECT, cls.project, ignore=shutil.ignore_patterns(".godot"))
        # --check-only resolves `class_name` types through the global class cache, which a fresh
        # copy has not built yet. Let the editor perform its normal headless scan first.
        subprocess.run(
            [cls.godot, "--editor", "--headless", "--path", str(cls.project), "--quit"],
            cwd=REPO, capture_output=True, text=True, check=False,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def test_every_script_parses_and_resolves(self) -> None:
        scripts = sorted(
            path.relative_to(self.project).as_posix()
            for path in self.project.rglob("*.gd")
        )
        self.assertGreater(len(scripts), 20, "script sweep found suspiciously few .gd files")

        for relative in scripts:
            with self.subTest(script=relative):
                result = subprocess.run(
                    [self.godot, "--headless", "--path", str(self.project),
                     "--check-only", "--script", "res://" + relative],
                    cwd=REPO, capture_output=True, text=True, check=False,
                )
                self.assertEqual(
                    0, result.returncode,
                    f"res://{relative} failed to parse/resolve:\n"
                    f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}",
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
