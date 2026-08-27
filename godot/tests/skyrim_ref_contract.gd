extends SceneTree
## Headless probe for tests/test_skyrim_ref.py. Exercises the shared ref rules that TexFetch and
## ModelFetch feed straight into cache filenames and CLI argv, plus the shape of RepoLayout.resolve().
## Runs only in that harness's temporary project copy.

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var result_path: String = OS.get_cmdline_user_args()[0]

	# Accepted: a well-formed ref, in either hex case and with or without leading zeros.
	for good in ["Skyrim.esm:0x018199", "Skyrim.esm:0x18199", "skyrim.esm:0x01a2b3",
			"Dawnguard.esm:0x000C14", "Skyrim.esm:0xFFFFFF", "Skyrim.esm:0x0"]:
		_check(SkyrimRef.is_valid(good), "rejected a well-formed ref: " + good)

	# Rejected. The traversal cases are the reason this function exists: the ref becomes a filename
	# under res://texcache / res://modelcache and an argv entry for the ModForge CLI.
	for bad in [
			"",                          # nothing typed yet
			"Skyrim.esm",                # no FormID part
			":0x018199",                 # empty master
			"../../../etc/passwd:0x1",   # parent-dir escape
			"..:0x000001",               # bare ..
			"sub/dir:0x000001",          # posix separator
			"sub\\dir:0x000001",         # windows separator
			"Skyrim.esm:0xZZZZ",         # non-hex FormID
			"Skyrim.esm:0x",             # empty FormID
			"Skyrim.esm:0x123456789",    # FormID too long
			"Skyrim.esm:0x01000000",     # past the 24 bits the text form carries
		]:
		_check(not SkyrimRef.is_valid(bad), "accepted a bad ref: '%s'" % bad)

	# One spelling per record, so two spellings cannot occupy two cache entries.
	_check(SkyrimRef.canonical("Skyrim.esm:0x18199") == "Skyrim.esm:0x018199", "leading zeros not padded")
	_check(SkyrimRef.canonical("Skyrim.esm:0x00018199") == "Skyrim.esm:0x018199", "extra zeros not trimmed")
	_check(SkyrimRef.canonical("Skyrim.esm:0x01a2b3") == "Skyrim.esm:0x01A2B3", "hex case not normalised")
	_check(SkyrimRef.canonical("Skyrim.esm:0x018199") == "Skyrim.esm:0x018199", "canonical is not idempotent")
	# The cache filename stem the fetchers build from a canonical ref must stay path-safe.
	var stem := SkyrimRef.canonical("Skyrim.esm:0x18199").replace(":", "_")
	_check(not stem.contains("/") and not stem.contains("\\") and not stem.contains(".."),
		"canonical ref produced an unsafe filename stem: " + stem)

	# RepoLayout: the contract TexFetch and ModelFetch both read.
	var layout := RepoLayout.resolve()
	for key in ["data_dir", "cli_project", "mc_dir", "mc_python"]:
		_check(layout.has(key), "RepoLayout.resolve() lost key: " + key)
	_check(layout["cli_project"].ends_with("ModForge/src/ModForge.Cli"),
		"ModForge CLI path drifted: " + str(layout["cli_project"]))
	_check(layout["mc_dir"].ends_with("model-converter"),
		"model-converter path drifted: " + str(layout["mc_dir"]))
	_check(layout["mc_python"].begins_with(layout["mc_dir"]),
		"venv python escaped the model-converter checkout: " + str(layout["mc_python"]))
	_check(RepoLayout.default_python("/tmp/mc").begins_with("/tmp/mc/.venv/"),
		"default_python no longer points into the checkout's venv")

	var file := FileAccess.open(result_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": _failures}))
	file.close()
	quit(0 if _failures.is_empty() else 1)
