class_name IoPng

static func export_dialog(host: Node, terrain: TerrainGrid, lbl_brush: Label) -> void:
	var dlg := FileDialog.new()
	dlg.access       = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode    = FileDialog.FILE_MODE_SAVE_FILE
	dlg.filters      = PackedStringArray(["*.png ; 16-bit Grayscale PNG"])
	dlg.current_file = "terrain.png"
	dlg.confirmed.connect(func():
		var ok := Png16.save(dlg.current_path, terrain.verts_x, terrain.verts_y,
			terrain.heights, terrain.min_height, terrain.max_height)
		if ok:
			print("Exported → " + dlg.current_path)
			if lbl_brush: lbl_brush.text = "Saved: " + dlg.current_path.get_file()
		else:
			push_error("Export failed: " + dlg.current_path)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


static func import_dialog(host: Node, terrain: TerrainGrid) -> void:
	var dlg := FileDialog.new()
	dlg.access    = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.filters   = PackedStringArray(["*.png ; PNG Heightmap"])
	dlg.confirmed.connect(func():
		var h := Png16.load_heights(dlg.current_path, terrain.verts_x, terrain.verts_y,
			terrain.min_height, terrain.max_height)
		if not h.is_empty():
			terrain.heights = h
			terrain.rebuild_mesh()
			print("Imported: " + dlg.current_path)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)
