class_name EditorInput
## Editor input routing for the root scene: keyboard brush-mode hotkeys, LMB place/paint dispatch,
## and the per-frame cursor + height-readout + paint tick. Split out of main.gd; operates on the
## passed root `m` (its terrain / camera_rig / tools / mode flags). Walk mode owns input separately.

static func input(m: WorldspaceEditor, event: InputEvent) -> void:
	if m._player != null:
		return  # walk mode owns input
	# Brush mode is chosen from the side-panel buttons; WASD now drives camera panning, so the old
	# R/L/F/S key shortcuts are gone (S would have fought "move back").

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if over_ui(m, event.position):
			return
		if m._place_mode:
			if event.pressed:
				var hit := m.terrain.get_hit_position(m.camera_rig.get_camera(), event.position)
				if hit != Vector3.ZERO:
					m._placement.place_at(hit)
		else:
			# Both height-brush and splat modes paint on LMB drag (routed in process()).
			m._painting = event.pressed
			if m._painting and not m._splat_mode and m.terrain.brush_mode == TerrainGrid.BrushMode.FLATTEN:
				m.terrain.flatten_height = mid_height_at_mouse(m)


static func process(m: WorldspaceEditor, delta: float) -> void:
	var mouse := m.get_viewport().get_mouse_position()
	var cam   := m.camera_rig.get_camera()
	var hit   := m.terrain.get_hit_position(cam, mouse)

	m._cursor.visible = (hit != Vector3.ZERO and not over_ui(m, mouse))
	if hit != Vector3.ZERO:
		m._cursor.global_position = hit
		m._update_cursor()
		var vc  := m.terrain.world_to_vert(hit)
		var col := clampi(vc.x, 0, m.terrain.verts_x - 1)
		var row := clampi(vc.y, 0, m.terrain.verts_y - 1)
		var h   := m.terrain.get_height(col, row)
		if m._lbl_pos:
			m._lbl_pos.text = "col %d  row %d\nH: %.0f units" % [col, row, h]

	if m._painting and hit != Vector3.ZERO and not over_ui(m, mouse):
		if m._splat_mode:
			m._splat.paint(hit, delta)
		else:
			m.terrain.apply_brush(hit, delta)


static func mid_height_at_mouse(m: WorldspaceEditor) -> float:
	var cam := m.camera_rig.get_camera()
	var hit := m.terrain.get_hit_position(cam, m.get_viewport().get_mouse_position())
	if hit == Vector3.ZERO:
		return (m.terrain.min_height + m.terrain.max_height) * 0.5
	var vc := m.terrain.world_to_vert(hit)
	return m.terrain.get_height(clampi(vc.x, 0, m.terrain.verts_x - 1),
		clampi(vc.y, 0, m.terrain.verts_y - 1))


static func over_ui(m: WorldspaceEditor, screen_pos: Vector2) -> bool:
	return screen_pos.x < m._ui_width
