class_name ModelFetch
extends Node
## Resolves a Skyrim base ref ("master:0xFORMID") to a real 3D model node, so a placed object shows
## its actual vanilla mesh instead of a box proxy. Two-stage, mirroring TexFetch:
##   1. ModForge CLI `nifexport`            → extract the base's model .nif from the game mesh BSAs
##   2. nif2gltf executable/fallback         → convert the .nif to a flat glTF proxy
## The .gltf is cached under res://modelcache/ and loaded at runtime via GLTFDocument. Main-machine
## only (needs game data + dotnet + a model-converter executable); on failure callers keep the box.

const CACHE_REL := "res://modelcache"

var _cache: Dictionary = {}   # ref -> Node3D template (duplicated per placement); null = unresolvable
var _data_dir: String = ""
var _cli_project: String = ""
var _mc_dir: String = ""      # the sibling model-converter repo
var _mc_python: String = ""   # its .venv python
var _converter_executable: String = ""
var _converter_prefix: Array[String] = []
var _converter_source: String = ""

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
	_configure_converter()


static func _default_python(mc_dir: String) -> String:
	var relative := ".venv/Scripts/python.exe" if OS.get_name() == "Windows" else ".venv/bin/python"
	return mc_dir.path_join(relative)


# Invocation priority is part of the public model-converter protocol:
#   1. MODFORGE_NIF2GLTF_BIN: backend-agnostic executable, receives protocol args directly.
#   2. Predictable sibling checkout fallback: its venv Python runs `-m nif2gltf`.
# An explicitly configured but missing env hook does not silently fall back to a different backend.
static func _select_converter(mc_python: String) -> Dictionary:
	var hook := OS.get_environment("MODFORGE_NIF2GLTF_BIN").strip_edges()
	if hook != "":
		return {"executable": hook, "prefix": [], "source": "env"}
	return {"executable": mc_python, "prefix": ["-m", "nif2gltf"], "source": "sibling"}


func _configure_converter() -> void:
	var selected := _select_converter(_mc_python)
	_converter_executable = selected.executable
	_converter_prefix.assign(selected.prefix)
	_converter_source = selected.source


func available() -> bool:
	return _data_dir != "" and DirAccess.dir_exists_absolute(_cli_project) \
		and FileAccess.file_exists(_converter_executable)


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
	return _load_gltf_or_cleanup(gltf_abs)


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
	# 2) convert .nif -> .gltf through the public executable hook, or the sibling fallback.
	return _run_converter(nif_abs, gltf_abs)


func _run_converter(nif_abs: String, gltf_abs: String) -> bool:
	var bin_abs := gltf_abs.get_basename() + ".bin"
	# Never let a failed process or missing sidecar inherit a stale success at the same cache key.
	_remove_gltf_pair(gltf_abs)
	var out: Array = []
	if _converter_executable == "" or not FileAccess.file_exists(_converter_executable):
		push_warning("ModelFetch: nif2gltf executable is unavailable: " + _converter_executable)
		return false

	# Only the sibling `python -m` fallback needs PYTHONPATH; an env-hook executable owns its runtime.
	var had_pythonpath := OS.has_environment("PYTHONPATH")
	var old_pythonpath := OS.get_environment("PYTHONPATH")
	if _converter_source == "sibling":
		var separator := ";" if OS.get_name() == "Windows" else ":"
		var pythonpath := _mc_dir
		if old_pythonpath != "":
			pythonpath += separator + old_pythonpath
		OS.set_environment("PYTHONPATH", pythonpath)
	var args := _converter_prefix.duplicate()
	args.append_array(["--in", nif_abs, "--out", gltf_abs, "--flat"])
	var code := OS.execute(_converter_executable, args, out, true)
	if _converter_source == "sibling":
		if had_pythonpath:
			OS.set_environment("PYTHONPATH", old_pythonpath)
		else:
			OS.unset_environment("PYTHONPATH")
	if code != 0 or not FileAccess.file_exists(gltf_abs) or not FileAccess.file_exists(bin_abs):
		_remove_gltf_pair(gltf_abs)
		push_warning("ModelFetch: nif2gltf failed (code %d): %s" % [code, "\n".join(out)])
		return false
	return true


static func _remove_gltf_pair(gltf_abs: String) -> void:
	for path in [gltf_abs, gltf_abs.get_basename() + ".bin"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# Cache publication is only successful once Godot can consume the pair. A converter may exit 0
# while writing malformed JSON/buffer data; remove that poisoned key so a later explicit fetch retries.
func _load_gltf_or_cleanup(gltf_abs: String) -> Node3D:
	var scene := _load_gltf(gltf_abs)
	if scene == null:
		_remove_gltf_pair(gltf_abs)
	return scene


func _load_gltf(gltf_abs: String) -> Node3D:
	if not FileAccess.file_exists(gltf_abs):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(gltf_abs, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	return scene if scene is Node3D else null
