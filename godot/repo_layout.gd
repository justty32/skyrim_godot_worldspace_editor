class_name RepoLayout
## Where the two tools that live OUTSIDE this repo are, plus the game's Data dir.
##
## Defaults come from the sibling-repo layout: res:// is <projects>/godot-worldspace-editor/godot,
## so ModForge is <projects>/ModForge and model-converter is <projects>/model-converter. Anyone
## who clones the three repos elsewhere overrides the values in res://texconfig.json (gitignored).
## See ../design/frontend-structure.md § 外部工具路徑.
##
## TexFetch and ModelFetch each derived this independently; TexFetch resolved a subset and could
## therefore drift from the model path's idea of the same Data dir. Resolving once keeps them equal.

## Candidate Skyrim SE Data dirs (first that exists wins). Override via res://texconfig.json.
const DATA_CANDIDATES := [
	"/home/lorkhan/.local/share/Steam/steamapps/common/Skyrim Special Edition/Data",
	"/home/lorkhan/.steam/steam/steamapps/common/Skyrim Special Edition/Data",
]

const CONFIG_PATH := "res://texconfig.json"


## The model-converter venv interpreter implied by its checkout root.
static func default_python(mc_dir: String) -> String:
	var relative := ".venv/Scripts/python.exe" if OS.get_name() == "Windows" else ".venv/bin/python"
	return mc_dir.path_join(relative)


## { "data_dir", "cli_project", "mc_dir", "mc_python" }. data_dir is "" when no candidate exists
## and texconfig.json does not name one — that is what makes available() false on an offline machine.
## Note mc_python is re-derived from an overridden mc_dir, so overriding only mc_dir stays coherent.
static func resolve() -> Dictionary:
	var proj := ProjectSettings.globalize_path("res://").rstrip("/")
	var siblings := proj.get_base_dir().get_base_dir()  # …/godot → …/godot-worldspace-editor → <projects>
	var out := {
		"data_dir": "",
		"cli_project": siblings.path_join("ModForge/src/ModForge.Cli"),
		"mc_dir": siblings.path_join("model-converter"),
	}
	out["mc_python"] = default_python(out["mc_dir"])
	for d in DATA_CANDIDATES:
		if DirAccess.dir_exists_absolute(d):
			out["data_dir"] = d
			break
	if FileAccess.file_exists(CONFIG_PATH):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if cfg is Dictionary:
			out["data_dir"] = cfg.get("data_dir", out["data_dir"])
			out["cli_project"] = cfg.get("cli_project", out["cli_project"])
			out["mc_dir"] = cfg.get("mc_dir", out["mc_dir"])
			out["mc_python"] = cfg.get("mc_python", default_python(out["mc_dir"]))
	return out
