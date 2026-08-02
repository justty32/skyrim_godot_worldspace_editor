class_name TexFetch
extends Node
## Resolves a Skyrim LTEX ref ("master:0xFORMID") to a real Texture2D by shelling out to the
## ModForge CLI `texexport` (LTEX → diffuse .dds from the game's texture BSAs → PNG), caching the
## result under res://texcache/. This is what makes the terrain WYSIWYG: a splat layer shows its
## actual vanilla ground texture instead of a flat tint. Main-machine only (needs the game data +
## the dotnet CLI); when a fetch fails (offline machine, missing data) callers fall back to tints.

const CACHE_REL := "res://texcache"

var _cache: Dictionary = {}   # ref string -> Texture2D (or null if known-unresolvable)
var _data_dir: String = ""
var _cli_project: String = ""

# Candidate Skyrim SE Data dirs (first that exists wins). Override via res://texconfig.json.
const _DATA_CANDIDATES := [
	"/home/lorkhan/.local/share/Steam/steamapps/common/Skyrim Special Edition/Data",
	"/home/lorkhan/.steam/steam/steamapps/common/Skyrim Special Edition/Data",
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_REL))
	# Derive the CLI project from the repo layout: res:// = <repo>/sub_projs/godot-worldspace-editor/godot
	var proj := ProjectSettings.globalize_path("res://").rstrip("/")
	var repo := proj.get_base_dir().get_base_dir().get_base_dir()  # …/godot → …/godot-worldspace-editor → …/sub_projs → <repo>
	_cli_project = repo.path_join("src/ModForge.Cli")
	for d in _DATA_CANDIDATES:
		if DirAccess.dir_exists_absolute(d):
			_data_dir = d
			break
	_load_overrides()


func _load_overrides() -> void:
	if not FileAccess.file_exists("res://texconfig.json"):
		return
	var txt := FileAccess.get_file_as_string("res://texconfig.json")
	var cfg = JSON.parse_string(txt)
	if cfg is Dictionary:
		_data_dir = cfg.get("data_dir", _data_dir)
		_cli_project = cfg.get("cli_project", _cli_project)


func available() -> bool:
	return _data_dir != "" and DirAccess.dir_exists_absolute(_cli_project)


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


# Return the Texture2D for an LTEX ref. Loads a cached PNG instantly; only shells out to the CLI
# (slow, blocking) when allow_fetch=true and no PNG exists yet — so startup/painting stay snappy
# and the heavy export happens only on an explicit "load textures" / ref-commit action.
# null = unresolvable (or not fetched yet).
func get_texture(ref: String, allow_fetch: bool = false) -> Texture2D:
	if ref == "":
		return null
	if not _valid_ref(ref):   # user-entered text → keep it out of cache filenames / CLI args
		push_warning("TexFetch: ignoring malformed ref '%s' (expected '<master>:0xFORMID')" % ref)
		return null
	if _cache.has(ref) and _cache[ref] != null:
		return _cache[ref]

	var safe := ref.replace(":", "_")
	var png_abs := ProjectSettings.globalize_path(CACHE_REL).path_join(safe + ".png")
	if not FileAccess.file_exists(png_abs):
		if not allow_fetch:
			return null         # don't block; caller falls back to tint until an explicit fetch
		_run_export(ref)
	var tex := _load_png(png_abs)
	if tex != null:
		_cache[ref] = tex       # only cache successes; a failed/unfetched ref can retry later
	return tex


func _run_export(ref: String) -> void:
	if not available():
		push_warning("TexFetch: no data dir / CLI — '%s' falls back to tint" % ref)
		return
	var out_dir := ProjectSettings.globalize_path(CACHE_REL)
	var args := ["run", "--project", _cli_project, "-c", "Release", "--",
		"texexport", _data_dir, out_dir, ref]
	var output: Array = []
	var code := OS.execute("dotnet", args, output, true)
	if code != 0:
		push_warning("TexFetch: texexport %s failed (code %d): %s" % [ref, code, "\n".join(output)])


func _load_png(png_abs: String) -> Texture2D:
	if not FileAccess.file_exists(png_abs):
		return null
	var img := Image.new()
	if img.load(png_abs) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
