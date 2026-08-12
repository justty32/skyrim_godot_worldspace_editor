#!/usr/bin/env python3
"""Production model-converter -> Godot ModelFetch live contract."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GODOT_PROJECT = REPO / "godot"
MODEL_FETCH = GODOT_PROJECT / "model_fetch.gd"
PROBE_SCRIPT = "res://tests/model_fetch_contract.gd"
EXPECTED_POSITIONS = sorted(((1.0, 3.0, -2.0), (4.0, 8.0, -6.0), (-2.0, 7.0, -5.0)))


def executable_from_env_or_path(env_name: str, names: tuple[str, ...]) -> str | None:
    configured = os.environ.get(env_name)
    if configured:
        candidate = Path(configured).expanduser()
        return str(candidate.resolve()) if candidate.is_file() else None
    return next((found for name in names if (found := shutil.which(name))), None)


def sibling_repo(env_name: str, name: str) -> Path | None:
    configured = os.environ.get(env_name)
    candidate = Path(configured).expanduser() if configured else REPO.parent / name
    candidate = candidate.resolve()
    return candidate if candidate.is_dir() else None


def run(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def tree_signature(path: Path) -> tuple[tuple[str, int, int], ...]:
    if not path.exists():
        return ()
    return tuple(
        (str(item.relative_to(path)), item.stat().st_size, item.stat().st_mtime_ns)
        for item in sorted(path.rglob("*"))
        if item.is_file()
    )


def write_wrapper(
    path: Path,
    python: Path,
    model_converter: Path,
    exit_code: int | None = None,
    malformed: bool = False,
) -> None:
    if malformed:
        helper = path.with_suffix(".py")
        helper.write_text(
            """import pathlib, sys
args = sys.argv[1:]
out = pathlib.Path(args[args.index("--out") + 1])
out.write_text("{not glTF", encoding="utf-8")
out.with_suffix(".bin").write_bytes(b"not a glTF buffer")
""",
            encoding="utf-8",
        )
    if os.name == "nt":
        if malformed:
            body = f'@echo off\r\n"{python}" "{helper}" %*\r\n'
        elif exit_code is None:
            body = f'@echo off\r\nset "PYTHONPATH={model_converter}"\r\n"{python}" -m nif2gltf %*\r\n'
        else:
            body = f"@echo off\r\nexit /b {exit_code}\r\n"
    else:
        if malformed:
            body = f'#!/bin/sh\nexec "{python}" "{helper}" "$@"\n'
        elif exit_code is None:
            body = f'#!/bin/sh\nPYTHONPATH="{model_converter}" exec "{python}" -m nif2gltf "$@"\n'
        else:
            body = f"#!/bin/sh\nexit {exit_code}\n"
    path.write_text(body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class ModelFetchSourceContractTests(unittest.TestCase):
    def test_executable_hook_precedes_predictable_sibling_fallback(self) -> None:
        source = re.sub(r"\s+", "", MODEL_FETCH.read_text(encoding="utf-8"))
        expected = (
            'OS.get_environment("MODFORGE_NIF2GLTF_BIN")',
            'return{"executable":hook,"prefix":[],"source":"env"}',
            'return{"executable":mc_python,"prefix":["-m","nif2gltf"],"source":"sibling"}',
            '_converter_prefix.assign(selected.prefix)',
            'args.append_array(["--in",nif_abs,"--out",gltf_abs,"--flat"])',
            'code!=0ornotFileAccess.file_exists(gltf_abs)ornotFileAccess.file_exists(bin_abs)',
            'return_load_gltf_or_cleanup(gltf_abs)',
            'ifscene==null:_remove_gltf_pair(gltf_abs)',
        )
        for fragment in expected:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, source)


class ModelFetchLiveContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot"))
        cls.model_converter = sibling_repo("MODEL_CONVERTER_DIR", "model-converter")
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run ModelFetch live contract")
        if cls.model_converter is None:
            raise unittest.SkipTest("sibling model-converter not found; set MODEL_CONVERTER_DIR")

        relative_python = Path(".venv/Scripts/python.exe" if os.name == "nt" else ".venv/bin/python")
        cls.mc_python = cls.model_converter / relative_python
        if not cls.mc_python.is_file():
            raise unittest.SkipTest(f"model-converter venv missing: {cls.mc_python}")

    def test_synthetic_nif_loads_through_production_converter_and_model_fetch(self) -> None:
        cache_before = tree_signature(GODOT_PROJECT / ".godot")
        modelcache_before = tree_signature(GODOT_PROJECT / "modelcache")
        with tempfile.TemporaryDirectory(prefix="model_fetch_live_") as raw_temp:
            work = Path(raw_temp)
            # Godot's editor scan creates .godot and .gd.uid files. It only sees this disposable copy.
            godot_project = work / "godot"
            shutil.copytree(GODOT_PROJECT, godot_project, ignore=shutil.ignore_patterns(".godot"))
            nif_path = work / "asymmetric.nif"
            gltf_path = work / "asymmetric.gltf"
            result_path = work / "result.json"

            fixture_code = (
                "from pathlib import Path; from tests.nif_fixtures import build_le_nif; "
                f"Path({str(nif_path)!r}).write_bytes(build_le_nif("
                "[(1.,2.,3.),(4.,6.,8.),(-2.,5.,7.)],"
                "[(0.,0.,1.)]*3,[(0.,0.),(1.,0.),(0.,1.)],[(0,1,2)]))"
            )
            run([str(self.mc_python), "-c", fixture_code], self.model_converter)

            suffix = ".cmd" if os.name == "nt" else ""
            converter = work / f"nif2gltf-contract{suffix}"
            failing = work / f"nif2gltf-fail{suffix}"
            malformed = work / f"nif2gltf-malformed{suffix}"
            write_wrapper(converter, self.mc_python, self.model_converter)
            write_wrapper(failing, self.mc_python, self.model_converter, exit_code=7)
            write_wrapper(malformed, self.mc_python, self.model_converter, malformed=True)

            run([self.godot, "--editor", "--headless", "--path", str(godot_project), "--quit"], REPO)
            env = os.environ.copy()
            env["MODFORGE_NIF2GLTF_BIN"] = str(converter)
            run(
                [
                    self.godot,
                    "--headless",
                    "--path",
                    str(godot_project),
                    "--script",
                    PROBE_SCRIPT,
                    "--",
                    str(nif_path),
                    str(gltf_path),
                    str(failing),
                    str(malformed),
                    str(result_path),
                ],
                REPO,
                env,
            )

            result = json.loads(result_path.read_text(encoding="utf-8"))
            self.assertEqual([], result["failures"])
            self.assertTrue(result["node3d"])
            self.assertGreater(result["mesh_instances"], 0)
            self.assertEqual(1, result["primitives"])
            self.assertEqual(3, result["vertex_count"])
            actual = sorted(tuple(float(axis) for axis in point) for point in result["positions"])
            for actual_point, expected_point in zip(actual, EXPECTED_POSITIONS):
                for actual_axis, expected_axis in zip(actual_point, expected_point):
                    self.assertAlmostEqual(expected_axis, actual_axis, delta=0.001)

        self.assertEqual(cache_before, tree_signature(GODOT_PROJECT / ".godot"),
                         "live test polluted repo Godot cache")
        self.assertEqual(modelcache_before, tree_signature(GODOT_PROJECT / "modelcache"),
                         "live test polluted repo model cache")


if __name__ == "__main__":
    unittest.main(verbosity=2)
