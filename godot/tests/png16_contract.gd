extends SceneTree
## Headless producer/consumer probe for tests/test_png16_contract.py.
## Runs only in that harness's temporary project copy.


func _initialize() -> void:
	call_deferred("_run")


func _ints(values: PackedInt32Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(value)
	return result


func _floats_as_ints(values: PackedFloat32Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	return result


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("usage: png16_contract.gd -- <roundtrip.png> <five-filters.png> <result.json>")
		quit(2)
		return

	var roundtrip_path: String = args[0]
	var filtered_path: String = args[1]
	var result_path: String = args[2]
	var heights := PackedFloat32Array([
		0.0, 1.0, 255.0, 256.0, 257.0,
		32767.0, 32768.0, 4660.0, 65534.0, 65535.0,
	])
	if not Png16.save(roundtrip_path, 5, 2, heights, 0.0, 65535.0):
		quit(3)
		return

	var roundtrip_samples := Png16Codec.decode_l16(roundtrip_path, 5, 2)
	var roundtrip_heights := Png16.load_heights(roundtrip_path, 5, 2, 0.0, 65535.0)
	var filtered_samples := Png16Codec.decode_l16(filtered_path, 5, 5)
	if roundtrip_samples.is_empty() or roundtrip_heights.is_empty() or filtered_samples.is_empty():
		quit(4)
		return

	var result := FileAccess.open(result_path, FileAccess.WRITE)
	if result == null:
		quit(5)
		return
	result.store_string(JSON.stringify({
		"roundtrip_samples": _ints(roundtrip_samples),
		"roundtrip_heights": _floats_as_ints(roundtrip_heights),
		"filter_types": [0, 1, 2, 3, 4],
		"filtered_samples": _ints(filtered_samples),
	}))
	result.close()
	quit()
