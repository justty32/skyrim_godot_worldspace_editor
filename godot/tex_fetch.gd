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


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_REL))
	# Data dir + ModForge CLI location (sibling-repo defaults, texconfig.json overrides) — see RepoLayout.
	var layout := RepoLayout.resolve()
	_data_dir = layout["data_dir"]
	_cli_project = layout["cli_project"]


func available() -> bool:
	return _data_dir != "" and DirAccess.dir_exists_absolute(_cli_project)


# Return the Texture2D for an LTEX ref. Loads a cached PNG instantly; only shells out to the CLI
# (slow, blocking) when allow_fetch=true and no PNG exists yet — so startup/painting stay snappy
# and the heavy export happens only on an explicit "load textures" / ref-commit action.
# null = unresolvable (or not fetched yet).
func get_texture(ref: String, allow_fetch: bool = false) -> Texture2D:
	if ref == "":
		return null
	if not SkyrimRef.is_valid(ref):   # user-entered text → keep it out of cache filenames / CLI args
		push_warning("TexFetch: ignoring malformed ref '%s' (expected '<master>:0xFORMID')" % ref)
		return null
	ref = SkyrimRef.canonical(ref)
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
