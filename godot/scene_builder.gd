class_name SceneBuilder

static func environment(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color       = Color(0.2, 0.4, 0.7)
	sky_mat.sky_horizon_color   = Color(0.6, 0.7, 0.8)
	sky_mat.ground_bottom_color = Color(0.3, 0.28, 0.25)
	var sky := Sky.new(); sky.sky_material = sky_mat
	env.sky = sky
	var we := WorldEnvironment.new(); we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	parent.add_child(sun)


static func camera(parent: Node3D, terrain: TerrainGrid) -> CameraRig:
	var rig := CameraRig.new()
	parent.add_child(rig)
	var ds  := terrain.step * terrain.vis_surface_scale
	var cx  := (terrain.verts_x - 1) * ds * 0.5
	var cz  := -(terrain.verts_y - 1) * ds * 0.5
	var cy  := (terrain.max_height - terrain.min_height) * 0.5 \
		* TerrainGrid.METERS_PER_UNIT * terrain.vis_height_scale
	rig.target   = Vector3(cx, cy, cz)
	rig.distance = maxf((terrain.verts_x + terrain.verts_y) * ds * 0.4, 40.0)
	return rig


static func cursor(parent: Node3D) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = 0.0; m.outer_radius = 1.0; m.rings = 32; m.ring_segments = 8
	inst.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inst.material_override = mat
	inst.visible = false
	parent.add_child(inst)
	return inst


static func grid_outlines(parent: Node3D, cells_x: int, cells_y: int,
		terrain: TerrainGrid) -> Array[Node3D]:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ds     := terrain.step * terrain.vis_surface_scale
	var line_h := (terrain.max_height - terrain.min_height) * 0.5 \
		* TerrainGrid.METERS_PER_UNIT * terrain.vis_height_scale
	var lines: Array[Node3D] = []
	for cx in (cells_x + 1):
		var mesh := MeshInstance3D.new(); var bm := BoxMesh.new()
		var depth := (terrain.verts_y - 1) * ds
		bm.size = Vector3(0.2, 2.0, depth)
		mesh.mesh = bm; mesh.material_override = mat
		mesh.position = Vector3(cx * 32 * ds, line_h, -depth * 0.5)
		parent.add_child(mesh); lines.append(mesh)
	for cy in (cells_y + 1):
		var mesh := MeshInstance3D.new(); var bm := BoxMesh.new()
		var width := (terrain.verts_x - 1) * ds
		bm.size = Vector3(width, 2.0, 0.2)
		mesh.mesh = bm; mesh.material_override = mat
		mesh.position = Vector3(width * 0.5, line_h, -cy * 32 * ds)
		parent.add_child(mesh); lines.append(mesh)
	return lines
