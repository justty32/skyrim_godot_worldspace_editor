class_name ModelFetch
extends Node
## Resolves a Skyrim base ref ("master:0xFORMID") to a real 3D model node, so a placed object shows
## its actual vanilla mesh instead of a box proxy. Two-stage, mirroring TexFetch:
##   1. ModForge CLI `nifexport`            → extract the base's model .nif from the game mesh BSAs
##   2. nif2gltf (model-converter .venv)    → convert the .nif to a flat glTF proxy
## The .gltf is cached under res://modelcache/ and loaded at runtime via GLTFDocument. Main-machine
## only (needs game data + dotnet + the model-converter venv); when a fetch fails callers keep the box.

const CACHE_REL := "res://modelcache"

var _cache: Dictionary = {}   # ref -> Node3D template (duplicated per placement); null = unresolvable
var _data_dir: String = ""
var _cli_project: String = ""
var _mc_dir: String = ""      # the sibling model-converter repo
var _mc_python: String = ""   # its .venv python

const _DATA_CANDIDATES := [
	"/home/lorkhan/.local/share/Steam/steamapps/common/Skyrim Special Edition/Data",
	"/home/lorkhan/.steam/steam/steamapps/common/Skyrim Special Edition/Data",
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_REL))
	# Sibling-repo layout: res:// = <projects>/godot-worldspace-editor/godot, with ModForge and
	# model-converter cloned alongside under <projects>/. Override via res://texconfig.json.
	var proj := ProjectSettings.globalize_path("res://").rstrip("/")
	var siblings := proj.get_base_dir().get_base_dir()
	_cli_project = siblings.path_join("ModForge/src/ModForge.Cli")
	_mc_dir = siblings.path_join("model-converter")
	_mc_python = _default_python(_mc_dir)
	for d in _DATA_CANDIDATES:
		if DirAccess.dir_exists_absolute(d):
			_data_dir = d
			break
	if FileAccess.file_exists("res://texconfig.json"):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://texconfig.json"))
		if cfg is Dictionary:
			_data_dir = cfg.get("data_dir", _data_dir)
			_cli_project = cfg.get("cli_project", _cli_project)
			_mc_dir = cfg.get("mc_dir", _mc_dir)
			_mc_python = cfg.get("mc_python", _default_python(_mc_dir))


static func _default_python(mc_dir: String) -> String:
	var relative := ".venv/Scripts/python.exe" if OS.get_name() == "Windows" else ".venv/bin/python"
	return mc_dir.path_join(relative)


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
	if formid.length() < 1 or formid.length() > 8:
		return false
	for j in range(formid.length()):
		if "0123456789abcdefABCDEF".find(formid.substr(j, 1)) < 0:
			return false
	return formid.hex_to_int() <= 0xFFFFFF


static func _canonical_ref(ref: String) -> String:
	var i := ref.findn(":0x")
	return ref.substr(0, i) + ":0x%06X" % ref.substr(i + 3).hex_to_int()


# A fresh instance of the model for `ref`, or null. allow_fetch=true permits the slow CLI+convert
# for an uncached ref; false only loads an already-built glTF (keeps placing/startup snappy).
func get_model(ref: String, allow_fetch: bool = false) -> Node3D:
	if ref == "":
		return null
	if not _valid_ref(ref):   # user-entered text → keep it out of cache filenames / CLI args
		push_warning("ModelFetch: ignoring malformed ref '%s' (expected '<master>:0xFORMID')" % ref)
		return null
	ref = _canonical_ref(ref)
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
	# 2) convert .nif -> .gltf via the model-converter venv. Temporarily prepend the sibling repo
	# to PYTHONPATH because OS.execute cannot set a working directory or per-process environment.
	out = []
	var had_pythonpath := OS.has_environment("PYTHONPATH")
	var old_pythonpath := OS.get_environment("PYTHONPATH")
	var separator := ";" if OS.get_name() == "Windows" else ":"
	var pythonpath := _mc_dir
	if old_pythonpath != "":
		pythonpath += separator + old_pythonpath
	OS.set_environment("PYTHONPATH", pythonpath)
	var code := OS.execute(_mc_python, ["-m", "nif2gltf", "--in", nif_abs,
		"--out", gltf_abs, "--flat"], out, true)
	if had_pythonpath:
		OS.set_environment("PYTHONPATH", old_pythonpath)
	else:
		OS.unset_environment("PYTHONPATH")
	if code != 0 or not FileAccess.file_exists(gltf_abs):
		push_warning("ModelFetch: nif2gltf %s failed: %s" % [ref, "\n".join(out)])
		return false
	return true


func _load_gltf(gltf_abs: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(gltf_abs, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	return scene if scene is Node3D else null
