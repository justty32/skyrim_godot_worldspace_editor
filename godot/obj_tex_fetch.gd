class_name ObjTexFetch
extends Node
## Object diffuse PNGs, isolated by full path; failures retain the flat material.
const CACHE_REL := "res://texcache/obj"
const MAX_FETCH := 64
const MAX_BATCH := 32
const MAX_PNG_BYTES := 16 * 1024 * 1024
var _cache: Dictionary = {}
var _data_dir: String = ""
var _cli_project: String = ""

func _ready() -> void:
	var layout := RepoLayout.resolve()
	_data_dir = layout["data_dir"]
	_cli_project = layout["cli_project"]

static func normalized(path: String) -> String:
	return path.replace("\\", "/").to_lower()

static func cache_path(path: String) -> String:
	var key := normalized(path)
	return CACHE_REL.path_join(key.sha1_text().substr(0, 16)).path_join(key.get_file().get_basename() + ".png")

func available() -> bool:
	return _data_dir != "" and DirAccess.dir_exists_absolute(_cli_project)

func get_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var key := normalized(path)
	if _cache.has(key):
		return _cache[key]
	var png := ProjectSettings.globalize_path(cache_path(key))
	if FileAccess.file_exists(png):
		_cache[key] = _load_png(png)
		return _cache[key]
	return null

# Called once per existing Load real models action. Failed paths are remembered for this
# session so missing assets cannot starve later pages of the 64-path budget.
func fetch_paths(paths: Array[String]) -> int:
	var pending: Array[String] = []
	for path in paths:
		var key := normalized(path)
		if key != "" and get_texture(key) == null and not _cache.has(key) and not pending.has(key):
			pending.append(key)
	var selected: Array[String] = []
	selected.assign(pending.slice(0, MAX_FETCH))
	var batch: Array[String] = []
	var leaves: Array[String] = []
	for key in selected:
		var leaf := key.get_file().get_basename()
		# texpath writes basenames into one output directory: never batch colliding names.
		if batch.size() == MAX_BATCH or leaves.has(leaf):
			_run_export(batch)
			batch.clear()
			leaves.clear()
		batch.append(key)
		leaves.append(leaf)
	if not batch.is_empty():
		_run_export(batch)
	return maxi(0, pending.size() - selected.size())

func _run_export(paths: Array[String]) -> void:
	if not available():
		print("ObjTexFetch: no data dir / CLI; keeping flat materials")
		for path in paths:
			_cache[path] = null
		return
	var root := ProjectSettings.globalize_path(CACHE_REL)
	var staging := root.path_join("batch_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(staging)
	var output: Array = []
	var code := OS.execute("dotnet", ["run", "--project", _cli_project, "-c", "Release", "--",
		"texpath", _data_dir, staging, ",".join(paths)], output, true)
	if code != 0:
		print("ObjTexFetch: texpath incomplete; keeping flat materials for missing PNGs")
	for path in paths:
		var src := staging.path_join(path.get_file().get_basename() + ".png")
		var dst := ProjectSettings.globalize_path(cache_path(path))
		if FileAccess.file_exists(src):
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			DirAccess.rename_absolute(src, dst)
		_cache[path] = _load_png(dst)
	DirAccess.remove_absolute(staging)

func _load_png(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var size := file.get_length()
	file.close()
	if size > MAX_PNG_BYTES:
		print("ObjTexFetch: PNG exceeds 16 MB: " + path)
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
