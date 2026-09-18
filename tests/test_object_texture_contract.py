#!/usr/bin/env python3
"""Synthetic NIF -> sidecar and headless Godot diffuse consumer contract."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
DIFFUSE = r"textures\Clutter\Barrel02.dds"

FIXTURE = r'''
from pathlib import Path
import struct, sys
from tests import nif_fixtures as f
verts = [(0.,0.,0.),(1.,0.,0.),(0.,1.,0.)]
shape = bytearray(f._bstrishape_block(verts, [(0.,0.,1.)]*3, [(0.,0.),(1.,0.),(0.,1.)], [(0,1,2)]))
struct.pack_into('<i', shape, len(f._niavobject()) + 20, 3)
empty = f._bstrishape_block(verts, [(0.,0.,1.)]*3, [(0.,0.),(1.,0.),(0.,1.)], [(0,1,2)])
blocks = [f._ninode_block([1,2]), bytes(shape), empty, b'\0'*40 + f._i32(4), f._u32(1) + f._sized(sys.argv[2])]
types = ['NiNode','BSTriShape','BSLightingShaderProperty','BSShaderTextureSet']
Path(sys.argv[1]).write_bytes(f._header(types, [0,1,1,2,3], blocks, ['mesh'], f.BS_SSE) + b''.join(blocks))
'''

PROBE = r'''
extends SceneTree
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var fetch := ModelFetch.new()
	root.add_child(fetch)
	var sidecar: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var tex_path: String = sidecar.meshes[0].diffuse
	var png := ProjectSettings.globalize_path(ObjTexFetch.cache_path(tex_path))
	DirAccess.make_dir_recursive_absolute(png.get_base_dir())
	var img := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.CORAL)
	img.save_png(png)
	var obj := PlacedObject.new()
	root.add_child(obj)
	obj.setup("Skyrim.esm:0x000001", "", Color.GRAY)
	obj.texture_fetch = fetch.textures
	obj.set_model(fetch._load_gltf(args[0]))
	var meshes: Array[MeshInstance3D] = []
	PlacedObject._collect_meshes(obj._model, meshes)
	var flat: Array = []
	for mesh in meshes:
		flat.append(mesh.material_override)
	var degradation := meshes.size() == 2
	# Absent sidecar, blank diffuse, missing PNG, and no matching name/index retain flat.
	for metadata in [{}, {"contract":"gltf-textures/1", "meshes":[
		{"index":0,"name":"shape_1","diffuse":""},
		{"index":1,"name":"shape_2","diffuse":"textures/missing.dds"}]},
		{"contract":"gltf-textures/1", "meshes":[{"index":99,"name":"unknown","diffuse":tex_path}]}]:
		obj.apply_textures(metadata)
		for i in range(meshes.size()):
			degradation = degradation and meshes[i].material_override == flat[i]
	degradation = degradation and fetch.get_sidecar("Skyrim.esm:0x000001").is_empty()
	# Name beats a deliberately wrong index; unmatched name falls back to index.
	sidecar.meshes[0].index = 1
	sidecar.meshes[1].name = "unmatched"
	sidecar.meshes[1].diffuse = tex_path
	obj.apply_textures(sidecar)
	var applied := meshes.size() == 2
	for mesh in meshes:
		var mat = mesh.material_override
		applied = applied and mat is StandardMaterial3D
		if mat is StandardMaterial3D:
			applied = applied and mat.albedo_texture != null
			if mat.albedo_texture != null:
				applied = applied and mat.albedo_texture.get_width() == 8 and mat.albedo_texture.get_height() == 4
				applied = applied and mat.albedo_texture.get_image().has_mipmaps()
			for surface in range(mesh.mesh.get_surface_count()):
				applied = applied and mesh.get_surface_override_material(surface) == mat
	var a := ObjTexFetch.cache_path("textures/a/stone01.dds")
	var b := ObjTexFetch.cache_path("textures/b/stone01.dds")
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"applied":applied, "degradation":degradation,
		"key_a":a, "key_b":b, "key_case":ObjTexFetch.cache_path("TEXTURES\\A\\STONE01.DDS")}))
	file.close()
	obj.free()
	fetch.free()
	quit()
'''


class ObjectTextureContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        godot = os.environ.get("GODOT_BIN") or shutil.which("godot4") or shutil.which("godot") or shutil.which("godot-mono")
        mc = REPO.parent / "model-converter"
        python = mc / (".venv/Scripts/python.exe" if os.name == "nt" else ".venv/bin/python")
        if not godot or not python.is_file():
            raise unittest.SkipTest("Godot and sibling model-converter venv required")
        cls.temp = tempfile.TemporaryDirectory(prefix="object_texture_", dir=REPO)
        cls.addClassCleanup(cls.temp.cleanup)
        work = Path(cls.temp.name)
        project = work / "godot"
        shutil.copytree(REPO / "godot", project,
                        ignore=shutil.ignore_patterns(".godot", "modelcache", "texcache", "texconfig.json"))
        (project / "texconfig.json").write_text('{"data_dir":""}')
        (project / "object_probe.gd").write_text(PROBE)
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1", PYTHONPATH=str(mc))

        def run(command, cwd=REPO):
            result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=120)
            if result.returncode or "SCRIPT ERROR:" in result.stderr:
                raise AssertionError(f"{command}\n{result.stdout}\n{result.stderr}")

        nif = work / "synthetic.nif"
        gltf = work / "synthetic.gltf"
        sidecar = work / "synthetic.textures.json"
        run([str(python), "-B", "-c", FIXTURE, str(nif), DIFFUSE], mc)
        run([str(python), "-B", "-m", "nif2gltf", "--in", str(nif), "--out", str(gltf), "--flat"], mc)
        run([str(python), "-B", str(REPO / "tools/nif_textures.py"), str(nif)])
        cls.sidecar = json.loads(sidecar.read_text())
        run([godot, "--headless", "--editor", "--path", str(project), "--quit"])
        result_path = work / "result.json"
        run([godot, "--headless", "--path", str(project), "--script", "res://object_probe.gd",
             "--", str(gltf), str(sidecar), str(result_path)])
        cls.result = json.loads(result_path.read_text())

    def test_sidecar_generator(self):
        self.assertEqual(self.sidecar, {"contract": "gltf-textures/1", "source": "synthetic.nif", "meshes": [
            {"index": 0, "name": "shape_1", "diffuse": DIFFUSE},
            {"index": 1, "name": "shape_2", "diffuse": ""}]})

    def test_godot_applies_real_texture(self):
        self.assertTrue(self.result["applied"])

    def test_missing_texture_keeps_flat_material(self):
        self.assertTrue(self.result["degradation"])

    def test_same_basename_has_distinct_cache_directories(self):
        import hashlib
        a, b = self.result["key_a"], self.result["key_b"]
        self.assertNotEqual(a.rsplit("/", 1)[0], b.rsplit("/", 1)[0])
        self.assertEqual(a, self.result["key_case"])
        for key, source in [(a, "textures/a/stone01.dds"), (b, "textures/b/stone01.dds")]:
            self.assertEqual(key, "res://texcache/obj/" + hashlib.sha1(source.encode()).hexdigest()[:16] + "/stone01.png")


if __name__ == "__main__":
    unittest.main(verbosity=2)
