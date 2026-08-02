class_name PlacementsIo
## Export / import placements.json (see ../design/placements-format.md). Positions are
## written as canonical Godot-native metres (display scales divided out) so they
## round-trip through ModForge's godot4_y_up → Skyrim conversion.

static func export_dialog(host: Node, tool: PlacementTool, terrain: TerrainGrid,
		status: Label) -> void:
	var dlg := FileDialog.new()
	dlg.access       = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode    = FileDialog.FILE_MODE_SAVE_FILE
	dlg.filters      = PackedStringArray(["*.json ; Placements JSON"])
	dlg.current_file = "placements.json"
	dlg.confirmed.connect(func():
		var f := FileAccess.open(dlg.current_path, FileAccess.WRITE)
		if f:
			f.store_string(_serialize(tool, terrain)); f.close()
			print("Exported placements → " + dlg.current_path)
			if status: status.text = "Saved %d placements" % tool.count()
		else:
			push_error("Placements export failed: " + dlg.current_path)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


static func import_dialog(host: Node, tool: PlacementTool, terrain: TerrainGrid,
		status: Label) -> void:
	var dlg := FileDialog.new()
	dlg.access    = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.filters   = PackedStringArray(["*.json ; Placements JSON"])
	dlg.confirmed.connect(func():
		var n := _deserialize(dlg.current_path, tool, terrain)
		if n >= 0:
			print("Imported %d placements: %s" % [n, dlg.current_path])
			if status: status.text = "Loaded %d placements" % n
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


static func _serialize(tool: PlacementTool, terrain: TerrainGrid) -> String:
	var arr: Array = []
	for obj in tool.objects():
		var m := terrain.world_to_canonical_meters(obj.global_position)
		var entry := {
			"base":     obj.skyrim_base,
			"position": {"x": m.x, "y": m.y, "z": m.z},
			"rotation": {"x": obj.rotation.x, "y": obj.rotation.y, "z": obj.rotation.z},
			"scale":    obj.uniform_scale,
		}
		if obj.instance_id != "":
			entry["instanceId"] = obj.instance_id
		arr.append(entry)
	return JSON.stringify({
		"version": 1,
		"coordinate_system": "godot4_y_up",
		"placements": arr,
	}, "  ")


# Returns placement count, or -1 on parse failure.
static func _deserialize(path: String, tool: PlacementTool, terrain: TerrainGrid) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open: " + path); return -1
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("placements"):
		push_error("Not a placements document: " + path); return -1
	tool.clear_all()
	for entry: Dictionary in data["placements"]:
		var p: Dictionary = entry.get("position", {})
		var r: Dictionary = entry.get("rotation", {})
		var disp := terrain.canonical_meters_to_world(
			Vector3(p.get("x", 0.0), p.get("y", 0.0), p.get("z", 0.0)))
		tool.restore(
			entry.get("base", ""),
			entry.get("instanceId", ""),
			disp,
			Vector3(r.get("x", 0.0), r.get("y", 0.0), r.get("z", 0.0)),
			entry.get("scale", 1.0))
	return tool.count()
