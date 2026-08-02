class_name PlacementUi
## Appends the PLACEMENT section to the side panel: mode toggle, placement-pen
## fields (base ref / instance / rotation / scale), live count, and JSON I/O.
## Built as a standalone module so world_ui.gd stays focused on terrain/brush.

static func build(vbox: VBoxContainer, tool: PlacementTool,
		on_mode_toggle: Callable, on_export: Callable, on_import: Callable) -> void:
	# Whole placement group lives in a collapsible section; fill its content VBox.
	vbox = UiSection.make(vbox, "OBJECT (PLACEMENT)")

	var btn_mode := Button.new()
	btn_mode.text = "Place Mode (LMB drops object)"
	btn_mode.toggle_mode = true
	btn_mode.toggled.connect(on_mode_toggle)
	vbox.add_child(btn_mode)

	_lbl(vbox, "Base ref:")
	var base_edit := LineEdit.new()
	base_edit.text = tool.current_base
	base_edit.placeholder_text = "Skyrim.esm:0xFORMID"
	base_edit.text_changed.connect(func(t: String): tool.current_base = t)
	vbox.add_child(base_edit)

	_lbl(vbox, "Instance ID (optional):")
	var inst_edit := LineEdit.new()
	inst_edit.placeholder_text = "blank = anonymous REFR"
	inst_edit.text_changed.connect(func(t: String): tool.current_instance_id = t)
	vbox.add_child(inst_edit)

	_lbl(vbox, "Rotation X (deg, tilt):")
	_slider_spin(vbox, 0.0, 359.0, 0.0, 1.0,
		func(v: float): tool.current_rot_x = deg_to_rad(v))

	_lbl(vbox, "Rotation Y (deg, yaw):")
	_slider_spin(vbox, 0.0, 359.0, 0.0, 1.0,
		func(v: float): tool.current_rot_y = deg_to_rad(v))

	_lbl(vbox, "Rotation Z (deg, tilt):")
	_slider_spin(vbox, 0.0, 359.0, 0.0, 1.0,
		func(v: float): tool.current_rot_z = deg_to_rad(v))

	_lbl(vbox, "Scale:")
	_slider_spin(vbox, 0.1, 10.0, 1.0, 0.1,
		func(v: float): tool.current_scale = v)

	var lbl_count := _lbl(vbox, "Objects: 0")
	tool.changed.connect(func(): lbl_count.text = "Objects: %d" % tool.count())

	var hbox := HBoxContainer.new(); vbox.add_child(hbox)
	var btn_undo := Button.new(); btn_undo.text = "Undo"
	btn_undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_undo.pressed.connect(tool.remove_last); hbox.add_child(btn_undo)
	var btn_clear := Button.new(); btn_clear.text = "Clear"
	btn_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_clear.pressed.connect(tool.clear_all); hbox.add_child(btn_clear)

	# Pull real vanilla meshes (nif→glTF via the CLI) and swap box proxies — the WYSIWYG trigger.
	# First fetch per base blocks a few seconds; results cache to res://modelcache/.
	var btn_mdl := Button.new(); btn_mdl.text = "Load real models (WYSIWYG)"
	btn_mdl.pressed.connect(func(): tool.refresh_models(true)); vbox.add_child(btn_mdl)

	var btn_exp := Button.new(); btn_exp.text = "Save placements.json"
	btn_exp.pressed.connect(on_export); vbox.add_child(btn_exp)
	var btn_imp := Button.new(); btn_imp.text = "Load placements.json"
	btn_imp.pressed.connect(on_import); vbox.add_child(btn_imp)


static func _lbl(parent: Control, text: String, bold: bool = false) -> Label:
	var lbl := Label.new(); lbl.text = text
	if bold: lbl.add_theme_font_size_override("font_size", 13)
	parent.add_child(lbl)
	return lbl


static func _slider_spin(parent: Control, min_v: float, max_v: float,
		init_v: float, step_v: float, cb: Callable) -> void:
	var hbox := HBoxContainer.new(); parent.add_child(hbox)
	var sl := HSlider.new()
	sl.min_value = min_v; sl.max_value = max_v; sl.value = init_v; sl.step = step_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hbox.add_child(sl)
	var sp := SpinBox.new()
	sp.min_value = min_v; sp.max_value = max_v; sp.value = init_v; sp.step = step_v
	sp.custom_minimum_size.x = 70; hbox.add_child(sp)
	sl.value_changed.connect(func(v: float): sp.value = v; cb.call(v))
	sp.value_changed.connect(func(v: float): sl.value = v)
