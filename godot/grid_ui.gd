class_name GridUi
## Appends the GRID section to the side panel: live cell/vert dims + buttons to add or remove a
## cell column on the East (X+) or a cell row on the North (Y+). Growth keeps the SW origin fixed
## (TerrainGrid.resize_cells), so existing heights/placements/splatmaps stay registered.
## Standalone module like PlacementUi / SplatUi so world_ui.gd stays focused on terrain/brush.

static func build(vbox: VBoxContainer, terrain: TerrainGrid, on_add_cells: Callable) -> void:
	vbox.add_child(HSeparator.new())
	_lbl(vbox, "GRID (CELLS)", true)

	var lbl_dims := _lbl(vbox, "")
	var refresh := func():
		lbl_dims.text = "%d×%d cells  (%d×%d verts)" % [
			terrain.cells_x, terrain.cells_y, terrain.verts_x, terrain.verts_y]
	refresh.call()
	terrain.terrain_changed.connect(refresh)   # resize_cells emits this → dims stay live

	var add_box := HBoxContainer.new(); vbox.add_child(add_box)
	_btn(add_box, "+ Cell E (X+)", func(): on_add_cells.call(1, 0))
	_btn(add_box, "+ Cell N (Y+)", func(): on_add_cells.call(0, 1))

	var del_box := HBoxContainer.new(); vbox.add_child(del_box)
	_btn(del_box, "− Cell E", func(): on_add_cells.call(-1, 0))
	_btn(del_box, "− Cell N", func(): on_add_cells.call(0, -1))


static func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)


static func _lbl(parent: Control, text: String, bold: bool = false) -> Label:
	var lbl := Label.new(); lbl.text = text
	if bold: lbl.add_theme_font_size_override("font_size", 13)
	parent.add_child(lbl)
	return lbl
