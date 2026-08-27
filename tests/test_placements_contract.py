#!/usr/bin/env python3
"""Godot exporter -> ModForge -> Skyrim REFR offline contract test.

The fast static test always runs. The headless producer test runs when Godot 4 is on PATH (or
GODOT_BIN points to it); the consumer half additionally needs a sibling ModForge checkout (or
MODFORGE_DIR). Nothing in this harness synthesizes placements.json: the runtime fixture comes from
PlacementsIo._serialize in the Godot project.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
GODOT_PROJECT = REPO / "godot"
EXPORTER = GODOT_PROJECT / "placements_io.gd"
COORDS = GODOT_PROJECT / "terrain_coords.gd"
PRODUCER_SCRIPT = "res://tests/placements_contract.gd"
METERS_PER_UNIT = 0.014286


def executable_from_env_or_path(env_name: str, names: tuple[str, ...]) -> str | None:
    configured = os.environ.get(env_name)
    if configured:
        candidate = Path(configured).expanduser()
        return str(candidate.resolve()) if candidate.is_file() else None
    return next((found for name in names if (found := shutil.which(name))), None)


def sibling_repo(env_name: str, sibling_name: str) -> Path | None:
    configured = os.environ.get(env_name)
    candidate = Path(configured).expanduser() if configured else REPO.parent / sibling_name
    candidate = candidate.resolve()
    return candidate if candidate.is_dir() else None


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    if result.returncode != 0:
        rendered = " ".join(command)
        raise AssertionError(
            f"command failed ({result.returncode}): {rendered}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def consumer_provenance(repo: Path) -> str:
    """Which ModForge tree this E2E actually exercised: short HEAD, plus whether it was dirty.

    The build fingerprint below only catches a rebuild DURING the test. It cannot tell that the
    tree was already dirty when we built it — and then a green run says nothing about the commit
    the parent repo has pinned, only about whatever was on disk. Report it rather than guess.
    """
    def git(*args: str) -> str | None:
        result = subprocess.run(
            ["git", "-C", str(repo), *args], text=True, capture_output=True
        )
        return result.stdout.strip() if result.returncode == 0 else None

    head = git("rev-parse", "--short", "HEAD")
    if head is None:
        return f"{repo} (not a git checkout)"
    dirty = git("status", "--porcelain")
    return f"{repo.name}@{head}" + (" DIRTY" if dirty else " clean")


def build_fingerprint(directory: Path) -> tuple[tuple[str, str], ...]:
    """SHA-256 of every file under `directory`, so a rebuild that changes content is detectable.

    `test_modforge_build_emits_matching_refr` builds the SIBLING ModForge checkout in place and then
    invokes it with `--no-build`. If anything else rebuilds that checkout in between — another agent
    line, an IDE, a file watcher — the CLI that runs is not the one this test built, and every
    assertion below it becomes a statement about someone else's tree. A deterministic rebuild of
    unchanged sources produces identical bytes, so this only fires when the binary really differs.
    """
    if not directory.is_dir():
        return ()
    return tuple(
        (str(item.relative_to(directory)), hashlib.sha256(item.read_bytes()).hexdigest())
        for item in sorted(directory.rglob("*"))
        if item.is_file()
    )


class ProducerSourceContractTests(unittest.TestCase):
    """Fail fast even on machines without Godot or ModForge installed."""

    def test_serializer_remains_the_contract_source(self) -> None:
        source = EXPORTER.read_text(encoding="utf-8")
        compact = re.sub(r"\s+", "", source)

        expected_fragments = (
            'constFORMAT_VERSION:=1',
            'constCOORDINATE_SYSTEM:="godot4_y_up"',
            'varm:=terrain.world_to_canonical_meters(obj.global_position)',
            '"base":obj.skyrim_base',
            '"position":{"x":m.x,"y":m.y,"z":m.z}',
            '"rotation":{"x":obj.rotation.x,"y":obj.rotation.y,"z":obj.rotation.z}',
            '"scale":obj.uniform_scale',
            'ifobj.instance_id!="":entry["instanceId"]=obj.instance_id',
            '"version":FORMAT_VERSION',
            '"coordinate_system":COORDINATE_SYSTEM',
            '"placements":arr',
        )
        for fragment in expected_fragments:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, compact)

        coord_source = re.sub(r"\s+", "", COORDS.read_text(encoding="utf-8"))
        for fragment in (
            "display_world.x/t.vis_surface_scale",
            "display_world.y/t.vis_height_scale+t.min_height*MPU",
            "display_world.z/t.vis_surface_scale",
        ):
            with self.subTest(coordinate_fragment=fragment):
                self.assertIn(fragment, coord_source)


class RuntimePlacementContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.godot = executable_from_env_or_path("GODOT_BIN", ("godot4", "godot", "godot-mono"))
        if cls.godot is None:
            raise unittest.SkipTest("Godot not found; set GODOT_BIN to run the producer/E2E test")

        cls.tempdir = tempfile.TemporaryDirectory(prefix="godot_modforge_contract_")
        cls.work = Path(cls.tempdir.name)
        # Godot 4.6's editor scan writes .gd.uid sidecars beside newly discovered scripts. Run the
        # real project from an isolated copy so a successful contract test never dirties the checkout.
        cls.godot_project = cls.work / "godot"
        shutil.copytree(GODOT_PROJECT, cls.godot_project, ignore=shutil.ignore_patterns(".godot"))
        cls.placements_path = cls.work / "placements.json"
        # A fresh checkout has no .godot/global_script_class_cache.cfg yet. Let the editor perform
        # its normal headless scan before --script parses references to the project's class_name types.
        run(
            [cls.godot, "--editor", "--headless", "--path", str(cls.godot_project), "--quit"],
            REPO,
        )
        run(
            [
                cls.godot,
                "--headless",
                "--path",
                str(cls.godot_project),
                "--script",
                PRODUCER_SCRIPT,
                "--",
                str(cls.placements_path),
            ],
            REPO,
        )
        cls.payload = json.loads(cls.placements_path.read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "tempdir"):
            cls.tempdir.cleanup()

    def test_headless_export_has_exact_v1_contract(self) -> None:
        self.assertEqual(1, self.payload["version"])
        self.assertEqual("godot4_y_up", self.payload["coordinate_system"])
        self.assertEqual(2, len(self.payload["placements"]))

        named, anonymous = self.payload["placements"]
        self.assertEqual("ContractRock", named["base"])
        self.assertEqual("ContractPlacement", named["instanceId"])
        self.assertEqual(1.5, named["scale"])
        self.assertAlmostEqual(12.5, named["position"]["x"], places=5)
        self.assertAlmostEqual(60.344, named["position"]["y"], places=4)
        self.assertAlmostEqual(-8.1, named["position"]["z"], places=5)
        self.assertAlmostEqual(0.25, named["rotation"]["x"], places=5)
        self.assertAlmostEqual(math.pi / 2.0, named["rotation"]["y"], places=5)
        self.assertAlmostEqual(-0.5, named["rotation"]["z"], places=5)
        self.assertNotIn("instanceId", anonymous)

    def test_modforge_build_emits_matching_refr(self) -> None:
        modforge = sibling_repo("MODFORGE_DIR", "ModForge")
        if modforge is None:
            self.skipTest("sibling ModForge checkout not found; set MODFORGE_DIR to run consumer E2E")

        provenance = consumer_provenance(modforge)
        # Printed on pass as well as failure: "green" here is a statement about THIS tree.
        print(f"\n  [consumer E2E] built against {provenance}", file=sys.stderr)

        cli_project = modforge / "src" / "ModForge.Cli" / "ModForge.Cli.csproj"
        run(["dotnet", "build", str(cli_project), "--nologo"], modforge)
        cli_output = cli_project.parent / "bin" / "Debug"
        built = build_fingerprint(cli_output)
        self.assertNotEqual((), built, f"dotnet build left no artifacts under {cli_output}")

        spec_path = self.work / "contract_spec.json"
        plugin_path = self.work / "ContractPlacement.esp"
        spec_path.write_text(
            json.dumps(
                {
                    "pluginName": plugin_path.name,
                    "esl": False,
                    "statics": [{"editorId": "ContractRock", "model": ""}],
                    "worldspaces": [
                        {
                            "editorId": "ContractWorld",
                            "godotPlacements": {
                                "path": str(self.placements_path),
                                "originX": 2,
                                "originY": -3,
                            },
                        }
                    ],
                },
                indent=2,
            ),
            encoding="utf-8",
        )

        cli = ["dotnet", "run", "--project", str(cli_project), "--no-build", "--"]
        build = run(cli + ["build", str(spec_path), str(plugin_path)], modforge)
        # Check this BEFORE the assertions below, so a concurrent rebuild reads as its own cause
        # rather than as a confusing content mismatch further down.
        self.assertEqual(
            built,
            build_fingerprint(cli_output),
            "the ModForge CLI binaries changed between `dotnet build` and `dotnet run --no-build`:"
            " something else rebuilt the sibling checkout mid-test (another agent line, an IDE, a"
            " watch task), so this ran a different binary than the one it built. Re-run with the"
            f" sibling repo quiet — do NOT read the assertions after this point as a pass."
            f" (built against {provenance})",
        )
        self.assertIn("2 placement(s)", build.stdout)
        self.assertTrue(plugin_path.is_file())

        # Read the written ESP back through ModForge's public PluginIo API. The tiny probe is built
        # in the temporary directory so this producer repo does not acquire a C# project or package
        # lockfiles merely to inspect Mutagen's final REFR representation.
        probe_dir = self.work / "probe"
        probe_dir.mkdir()
        core_project = modforge / "src" / "ModForge.Core" / "ModForge.Core.csproj"
        (probe_dir / "Probe.csproj").write_text(
            f"""<Project Sdk=\"Microsoft.NET.Sdk\">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup><ProjectReference Include=\"{core_project}\" /></ItemGroup>
</Project>
""",
            encoding="utf-8",
        )
        (probe_dir / "Program.cs").write_text(
            """using System.Text.Json;
using ModForge;
using Mutagen.Bethesda.Plugins.Records;
using Mutagen.Bethesda.Skyrim;

var mod = PluginIo.Load(args[0]);
var records = mod.EnumerateMajorRecords().ToList();
var placed = records.OfType<IPlacedObjectGetter>()
    .Single(record => record.EditorID == "ContractPlacement");
var position = placed.Placement!.Position;
var rotation = placed.Placement.Rotation;
var baseEditorId = records.Single(record => record.FormKey == placed.Base.FormKey).EditorID;
Console.WriteLine(JsonSerializer.Serialize(new {
    editorId = placed.EditorID,
    baseEditorId,
    position = new[] { position.X, position.Y, position.Z },
    rotation = new[] { rotation.X, rotation.Y, rotation.Z },
    scale = placed.Scale ?? 1.0f,
}));
""",
            encoding="utf-8",
        )
        probe = run(
            ["dotnet", "run", "--project", str(probe_dir / "Probe.csproj"), "--", str(plugin_path)],
            probe_dir,
        )
        refr = json.loads(probe.stdout.strip().splitlines()[-1])
        self.assertEqual("ContractPlacement", refr["editorId"])
        self.assertEqual("ContractRock", refr["baseEditorId"])

        expected_position = (
            2 * 4096 + 12.5 / METERS_PER_UNIT,
            -3 * 4096 - (-8.1 / METERS_PER_UNIT),
            60.344 / METERS_PER_UNIT,
        )
        expected_rotation_radians = (0.25, 0.5, math.pi / 2.0)
        for actual, expected in zip(refr["position"], expected_position):
            self.assertAlmostEqual(expected, actual, delta=0.05)
        for actual, expected in zip(refr["rotation"], expected_rotation_radians):
            self.assertAlmostEqual(expected, actual, delta=0.001)
        self.assertAlmostEqual(1.5, refr["scale"], places=5)


if __name__ == "__main__":
    unittest.main(verbosity=2)
