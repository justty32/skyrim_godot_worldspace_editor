class_name SplatmapIo
## Export/import a splat layer's alpha grid as an 8-bit grayscale PNG.
##
## Convention matches Png16 / the ModForge Heightmap & Splatmap loaders: PNG top row = world
## north (img_y=0 → world_row = verts_y-1), pixel 0..255 = alpha 0..1. The PNG width/height equal
## the terrain vertex grid (cells×32+1), so it co-registers with terrain.png. On export we also
## print a ready-to-paste `textureLayers` entry referencing the saved file + the layer's LTEX ref.

static func export_dialog(host: Node, splat: SplatTool, terrain: TerrainGrid, lbl: Label) -> void:
	var dlg := FileDialog.new()
	dlg.access       = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode    = FileDialog.FILE_MODE_SAVE_FILE
	dlg.filters      = PackedStringArray(["*.png ; 8-bit Grayscale Splatmap"])
	dlg.current_file = "splat_%d.png" % splat.active
	dlg.confirmed.connect(func():
		var ok := save_png(dlg.current_path, terrain, splat.layers[splat.active]["alpha"])
		if ok:
			var tex: String = splat.active_texture()
			print("Exported splatmap → " + dlg.current_path)
			print("  spec textureLayers entry:")
			print('  { "texture": "%s", "splatmap": { "path": "%s", "originX": 0, "originY": 0 } }'
				% [tex, dlg.current_path.get_file()])
			if lbl: lbl.text = "Saved: " + dlg.current_path.get_file()
		else:
			push_error("Splatmap export failed: " + dlg.current_path)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


static func import_dialog(host: Node, splat: SplatTool, terrain: TerrainGrid, lbl: Label) -> void:
	var dlg := FileDialog.new()
	dlg.access    = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.filters   = PackedStringArray(["*.png ; PNG Splatmap"])
	dlg.confirmed.connect(func():
		var a := load_alpha(dlg.current_path, terrain)
		if not a.is_empty():
			splat.layers[splat.active]["alpha"] = a
			SplatRender.refresh_visual(splat)   # rebuilds overlay + mesh (was a call to nonexistent SplatTool._push_overlay)
			splat.changed.emit()
			if lbl: lbl.text = "Loaded: " + dlg.current_path.get_file()
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


## alpha: PackedFloat32Array, size verts_x×verts_y, [row*verts_x+col], row0=south.
static func save_png(path: String, terrain: TerrainGrid, alpha: PackedFloat32Array) -> bool:
	var img := Image.create(terrain.verts_x, terrain.verts_y, false, Image.FORMAT_L8)
	for img_y in terrain.verts_y:
		var world_row := (terrain.verts_y - 1) - img_y   # top = north
		for col in terrain.verts_x:
			var v := clampf(alpha[world_row * terrain.verts_x + col], 0.0, 1.0)
			img.set_pixel(col, img_y, Color(v, v, v))
	return img.save_png(path) == OK


static func load_alpha(path: String, terrain: TerrainGrid) -> PackedFloat32Array:
	var img := Image.load_from_file(path)
	if img == null:
		push_error("Splatmap load: cannot load " + path)
		return PackedFloat32Array()
	if img.get_width() != terrain.verts_x or img.get_height() != terrain.verts_y:
		push_error("Splatmap load: size mismatch (expected %dx%d, got %dx%d)" % [
			terrain.verts_x, terrain.verts_y, img.get_width(), img.get_height()])
		return PackedFloat32Array()
	img.convert(Image.FORMAT_L8)
	var result := PackedFloat32Array()
	result.resize(terrain.verts_x * terrain.verts_y)
	for img_y in terrain.verts_y:
		var world_row := (terrain.verts_y - 1) - img_y
		for col in terrain.verts_x:
			result[world_row * terrain.verts_x + col] = img.get_pixel(col, img_y).r
	return result
