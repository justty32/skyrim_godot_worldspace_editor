class_name ModelFetch
extends Node
## Resolves a Skyrim base ref ("master:0xFORMID") to a real 3D model node, so a placed object shows
## its actual vanilla mesh instead of a box proxy. Two-stage, mirroring TexFetch:
##   1. ModForge CLI `nifexport`            → extract the base's model .nif from the game mesh BSAs
##   2. nif2gltf (model-converter .venv)    → convert the .nif to glTF
## The .gltf is cached under res://modelcache/ and loaded at runtime via GLTFDocument. Main-machine
## only (needs game data + dotnet + the model-converter venv); when a fetch fails callers keep the box.

const CACHE_REL := "res://modelcache"

var _cache: Dictionary = {}   # ref -> Node3D template (duplicated per placement); null = unresolvable
var _data_dir: String = ""
var _cli_project: String = ""
var _mc_dir: String = ""      # sub_projs/model-converter
var _mc_python: String = ""   # its .venv python

const _DATA_CANDIDATES := [
	"/home/lorkhan/.local/share/Steam/steamapps/common/Skyrim Special Edition/Data",
	"/home/lorkhan/.steam/steam/steamapps/common/Skyrim Special Edition/Data",
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_REL))
	var proj := ProjectSettings.globalize_path("res://").rstrip("/")
	var repo := proj.get_base_dir().get_base_dir().get_base_dir()
	_cli_project = repo.path_join("src/ModForge.Cli")
	_mc_dir = repo.path_join("sub_projs/model-converter")
	_mc_python = _mc_dir.path_join(".venv/bin/python")
	for d in _DATA_CANDIDATES:
		if DirAccess.dir_exists_absolute(d):
			_data_dir = d
			break
	if FileAccess.file_exists("res://texconfig.json"):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://texconfig.json"))
		if cfg is Dictionary:
			_data_dir = cfg.get("data_dir", _data_dir)
			_cli_project = cfg.get("cli_project", _cli_project)
			_mc_python = cfg.get("mc_python", _mc_python)


func available() -> bool:
	return _data_dir != "" and DirAccess.dir_exists_absolute(_cli_project) \
		and FileAccess.file_exists(_mc_python)


# A ref is "<master>:0xFORMID". Reject anything with path separators / ".." so a hand-typed ref can't
# escape the cache dir when turned into a filename, and so junk never reaches the CLI args.
static func _valid_ref(ref: String) -> bool:
	var i := ref.findn(":0x")
	if i <= 0:
		return false
	var master := ref.substr(0, i)
	var formid := ref.substr(i + 3)
	if master == "" or master.contains("/") or master.contains("\\") or master.contains(".."):
		return false
	return formid != "" and formid.is_valid_hex_number(false)


# A fresh instance of the model for `ref`, or null. allow_fetch=true permits the slow CLI+convert
# for an uncached ref; false only loads an already-built glTF (keeps placing/startup snappy).
func get_model(ref: String, allow_fetch: bool = false) -> Node3D:
	if ref == "":
		return null
	if not _valid_ref(ref):   # user-entered text → keep it out of cache filenames / CLI args
		push_warning("ModelFetch: ignoring malformed ref '%s' (expected '<master>:0xFORMID')" % ref)
		return null
	if not _cache.has(ref):
		_cache[ref] = _build_template(ref, allow_fetch)
	var tmpl: Node3D = _cache[ref]
	if tmpl == null:
		_cache.erase(ref)   # allow a later retry (e.g. after an explicit fetch)
		return null
	return tmpl.duplicate()


func _build_template(ref: String, allow_fetch: bool) -> Node3D:
	var safe := ref.replace(":", "_")
	var gltf_abs := ProjectSettings.globalize_path(CACHE_REL).path_join(safe + ".gltf")
	if not FileAccess.file_exists(gltf_abs):
		if not allow_fetch or not available():
			return null
		if not _export_and_convert(ref, gltf_abs):
			return null
	return _load_gltf(gltf_abs)


func _export_and_convert(ref: String, gltf_abs: String) -> bool:
	var cache_dir := ProjectSettings.globalize_path(CACHE_REL)
	var safe := ref.replace(":", "_")
	var nif_abs := cache_dir.path_join(safe + ".nif")
	# 1) extract the .nif from the game mesh BSAs via the ModForge CLI
	var out: Array = []
	if OS.execute("dotnet", ["run", "--project", _cli_project, "-c", "Release", "--",
			"nifexport", _data_dir, cache_dir, ref], out, true) != 0 or not FileAccess.file_exists(nif_abs):
		push_warning("ModelFetch: nifexport %s failed: %s" % [ref, "\n".join(out)])
		return false
	# 2) convert .nif -> .gltf via the model-converter venv. `env PYTHONPATH=<mc>` lets `-m nif2gltf`
	# resolve without depending on the process cwd (OS.execute doesn't set a working directory).
	out = []
	if OS.execute("env", ["PYTHONPATH=" + _mc_dir, _mc_python, "-m", "nif2gltf",
			"--in", nif_abs, "--out", gltf_abs, "--flat"], out, true) != 0 or not FileAccess.file_exists(gltf_abs):
		push_warning("ModelFetch: nif2gltf %s failed: %s" % [ref, "\n".join(out)])
		return false
	# 3) pull the model's diffuse textures (named in the <stem>.textures.json sidecar) out of the
	# game BSAs as <basename>.png next to the glTF, so GLTFDocument resolves its image uris → textured.
	_fetch_textures(cache_dir.path_join(safe + ".textures.json"), cache_dir)
	return true


# Extract the textures a glTF references (sidecar: {png_uri: nif_dds_path}) into out_dir as PNGs.
# Best-effort — a missing texture just leaves that material untextured, not a failure.
func _fetch_textures(sidecar_abs: String, out_dir: String) -> void:
	if not FileAccess.file_exists(sidecar_abs):
		return
	var map = JSON.parse_string(FileAccess.get_file_as_string(sidecar_abs))
	if not (map is Dictionary) or map.is_empty():
		return
	var dds_paths: Array = map.values()
	var out: Array = []
	OS.execute("dotnet", ["run", "--project", _cli_project, "-c", "Release", "--",
		"texpath", _data_dir, out_dir, ",".join(dds_paths)], out, true)


func _load_gltf(gltf_abs: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(gltf_abs, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	return scene if scene is Node3D else null
