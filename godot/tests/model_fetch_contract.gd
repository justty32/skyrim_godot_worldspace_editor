extends SceneTree
## Headless consumer probe for tests/test_model_fetch_contract.py.
## Runs only in that harness's temporary project copy.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _collect_meshes(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.mesh_instances += 1
		for surface in node.mesh.get_surface_count():
			result.primitives += 1
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			result.vertex_count += vertices.size()
			for vertex in vertices:
				result.positions.append([vertex.x, vertex.y, vertex.z])
	for child in node.get_children():
		_collect_meshes(child, result)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		push_error("usage: model_fetch_contract.gd -- <input.nif> <output.gltf> <bad-exec> <malformed-exec> <result.json>")
		quit(2)
		return
	var nif_path: String = args[0]
	var gltf_path: String = args[1]
	var bad_exec: String = args[2]
	var malformed_exec: String = args[3]
	var result_path: String = args[4]

	var fetch := ModelFetch.new()
	root.add_child(fetch)
	_check(fetch._converter_source == "env", "MODFORGE_NIF2GLTF_BIN must win")
	_check(fetch._converter_prefix.is_empty(), "env hook must receive protocol args directly")
	_check(fetch._run_converter(nif_path, gltf_path), "production converter invocation failed")
	_check(FileAccess.file_exists(gltf_path), "converter did not publish .gltf")
	var bin_path := gltf_path.get_basename() + ".bin"
	_check(FileAccess.file_exists(bin_path), "converter did not publish sibling .bin")

	var scene := fetch._load_gltf(gltf_path)
	_check(scene is Node3D, "GLTFDocument did not generate a Node3D")
	var mesh_result := {"mesh_instances": 0, "primitives": 0, "vertex_count": 0, "positions": []}
	if scene != null:
		_collect_meshes(scene, mesh_result)
	_check(mesh_result.mesh_instances > 0, "loaded scene contains no MeshInstance3D")
	_check(mesh_result.primitives > 0, "loaded scene contains no primitive surfaces")
	_check(mesh_result.vertex_count == 3, "expected exactly three synthetic vertices")

	var old_hook := OS.get_environment("MODFORGE_NIF2GLTF_BIN")
	# Missing external buffer must fail closed and remove the poisoned cache key.
	var missing_dir := gltf_path.get_base_dir().path_join("missing-bin")
	DirAccess.make_dir_recursive_absolute(missing_dir)
	var missing_gltf := missing_dir.path_join(gltf_path.get_file())
	var missing_file := FileAccess.open(missing_gltf, FileAccess.WRITE)
	missing_file.store_string(FileAccess.get_file_as_string(gltf_path))
	missing_file.close()
	_check(fetch._load_gltf_or_cleanup(missing_gltf) == null, "glTF with missing .bin was accepted")
	_check(not FileAccess.file_exists(missing_gltf), "missing-bin glTF was left cached")

	# Exit 0 with malformed output is not a success: consume, clean both files, then retry the same key.
	OS.set_environment("MODFORGE_NIF2GLTF_BIN", malformed_exec)
	var malformed := ModelFetch.new()
	root.add_child(malformed)
	var malformed_gltf := gltf_path.get_base_dir().path_join("malformed.gltf")
	_check(malformed._run_converter(nif_path, malformed_gltf), "malformed fixture must mimic exit-0 publication")
	_check(malformed._load_gltf_or_cleanup(malformed_gltf) == null, "malformed glTF was accepted")
	_check(not FileAccess.file_exists(malformed_gltf), "malformed .gltf poisoned the cache")
	_check(not FileAccess.file_exists(malformed_gltf.get_basename() + ".bin"), "malformed .bin poisoned the cache")
	OS.set_environment("MODFORGE_NIF2GLTF_BIN", old_hook)
	var retry := ModelFetch.new()
	root.add_child(retry)
	_check(retry._run_converter(nif_path, malformed_gltf), "cleaned cache key could not retry")
	_check(retry._load_gltf_or_cleanup(malformed_gltf) is Node3D, "retry did not load valid glTF")

	# A non-zero converter cannot leave stale/partial output looking successful.
	OS.set_environment("MODFORGE_NIF2GLTF_BIN", bad_exec)
	var failing := ModelFetch.new()
	root.add_child(failing)
	var failed_gltf := gltf_path.get_base_dir().path_join("failed.gltf")
	var stale_gltf := FileAccess.open(failed_gltf, FileAccess.WRITE)
	stale_gltf.store_string("stale")
	stale_gltf.close()
	var stale_bin := FileAccess.open(failed_gltf.get_basename() + ".bin", FileAccess.WRITE)
	stale_bin.store_8(1)
	stale_bin.close()
	_check(not failing._run_converter(nif_path, failed_gltf), "non-zero converter reported success")
	_check(not FileAccess.file_exists(failed_gltf), "failed converter left stale .gltf")
	_check(not FileAccess.file_exists(failed_gltf.get_basename() + ".bin"), "failed converter left stale .bin")

	# With no env hook, selection must deterministically fall back to sibling Python + -m nif2gltf.
	OS.unset_environment("MODFORGE_NIF2GLTF_BIN")
	var fallback := ModelFetch._select_converter("/expected/sibling/python")
	_check(fallback.source == "sibling", "missing hook did not select sibling fallback")
	_check(fallback.executable == "/expected/sibling/python", "fallback Python path drifted")
	_check(fallback.prefix == ["-m", "nif2gltf"], "fallback module prefix drifted")
	if old_hook == "":
		OS.unset_environment("MODFORGE_NIF2GLTF_BIN")
	else:
		OS.set_environment("MODFORGE_NIF2GLTF_BIN", old_hook)

	var result_file := FileAccess.open(result_path, FileAccess.WRITE)
	result_file.store_string(JSON.stringify({
		"failures": _failures,
		"node3d": scene is Node3D,
		"mesh_instances": mesh_result.mesh_instances,
		"primitives": mesh_result.primitives,
		"vertex_count": mesh_result.vertex_count,
		"positions": mesh_result.positions,
	}))
	result_file.close()
	quit(0 if _failures.is_empty() else 1)
