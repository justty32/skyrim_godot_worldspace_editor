#!/usr/bin/env python3
"""SkyrimRef / RepoLayout contract, executed by the real Godot runtime.

`SkyrimRef.is_valid` is the guard that stops a hand-typed base/LTEX ref from turning into a path
outside res://texcache / res://modelcache and from reaching the ModForge CLI's argv. It used to
exist as two byte-identical private copies (TexFetch._valid_ref, ModelFetch._valid_ref) with no
test on either. The assertions live in godot/tests/skyrim_ref_contract.gd so they run against the
production class, not a Python re-implementation of its rules.
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
PROBE_SCRIPT = "res://tests/skyrim_ref_contract.gd"


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


class SkyrimRefContractTests(unittest.TestCase):
    def test_ref_rules_and_layout_hold_in_the_godot_runtime(self) -> None:
        godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if godot is None:
            self.skipTest("Godot not found; set GODOT_BIN to run the SkyrimRef contract")

        with tempfile.TemporaryDirectory(prefix="skyrim_ref_contract_") as raw_temp:
            work = Path(raw_temp)
            # Same isolation rule as the other suites: the editor scan writes .gd.uid sidecars, so
            # it only ever sees a disposable copy of the checkout.
            project = work / "godot"
            shutil.copytree(GODOT_PROJECT, project, ignore=shutil.ignore_patterns(".godot"))
            result_path = work / "result.json"

            run([godot, "--editor", "--headless", "--path", str(project), "--quit"], REPO)
            run([godot, "--headless", "--path", str(project), "--script", PROBE_SCRIPT,
                 "--", str(result_path)], REPO)

            result = json.loads(result_path.read_text(encoding="utf-8"))
            self.assertEqual([], result["failures"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
