class_name WalkMode
## First-person "walk the terrain" preview: spawn a PlayerController at the terrain centre and
## suspend editor input, restore on exit. Split out of main.gd as a self-contained mode (operates
## on the passed root `m`, same as SceneBuilder builds into a passed parent).

static func enter(m: WorldspaceEditor) -> void:
	if m._player != null:
		return
	m.terrain.refresh_collision()
	m._player = PlayerController.new()
	m.add_child(m._player)
	# Spawn at terrain center, dropped in from just above the surface.
	var ds := m.terrain.step * m.terrain.vis_surface_scale
	var cc := m.terrain.verts_x / 2
	var cr := m.terrain.verts_y / 2
	var gy := (m.terrain.get_height(cc, cr) - m.terrain.min_height) \
		* TerrainGrid.METERS_PER_UNIT * m.terrain.vis_height_scale
	m._player.global_position = Vector3(cc * ds, gy + 3.0, -cr * ds)
	m._player.exited.connect(m._exit_walk_mode)
	m._player.activate()
	# Suspend editor: stop orbit input, WASD camera pan, cursor/paint processing.
	m.camera_rig.set_process_input(false)
	m.camera_rig.set_process(false)
	m.set_process(false)
	m._painting = false
	m._cursor.visible = false


static func exit(m: WorldspaceEditor) -> void:
	if m._player == null:
		return
	m._player.queue_free()
	m._player = null
	m.camera_rig.get_camera().current = true
	m.camera_rig.set_process_input(true)
	m.camera_rig.set_process(true)
	m.set_process(true)
