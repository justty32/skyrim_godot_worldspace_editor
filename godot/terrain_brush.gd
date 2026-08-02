class_name TerrainBrush

static func apply(t: TerrainGrid, hit_world: Vector3, delta: float) -> bool:
	var cv := t.world_to_vert(hit_world)
	var r  := int(ceilf(t.brush_radius))
	var changed := false
	for dr in range(-r, r + 1):
		for dc in range(-r, r + 1):
			var row := cv.y + dr
			var col := cv.x + dc
			if row < 0 or row >= t.verts_y or col < 0 or col >= t.verts_x:
				continue
			var dist := Vector2(float(dc), float(dr)).length()
			if dist > t.brush_radius:
				continue
			var falloff := 1.0 - smoothstep(0.0, t.brush_radius, dist)
			match t.brush_mode:
				TerrainGrid.BrushMode.RAISE:
					t.set_height(col, row, t.get_height(col, row) + delta * falloff * t.brush_strength)
				TerrainGrid.BrushMode.LOWER:
					t.set_height(col, row, t.get_height(col, row) - delta * falloff * t.brush_strength)
				TerrainGrid.BrushMode.FLATTEN:
					var h := t.get_height(col, row)
					t.set_height(col, row, lerpf(h, t.flatten_height, minf(delta * falloff * 3.0, 1.0)))
				TerrainGrid.BrushMode.SMOOTH:
					_smooth(t, col, row, delta * falloff)
			changed = true
	return changed


static func _smooth(t: TerrainGrid, col: int, row: int, v: float) -> void:
	var sum := 0.0; var cnt := 0
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			var nr: int = row + int(dr); var nc: int = col + int(dc)
			if nr >= 0 and nr < t.verts_y and nc >= 0 and nc < t.verts_x:
				sum += t.get_height(nc, nr); cnt += 1
	if cnt > 0:
		t.set_height(col, row, lerpf(t.get_height(col, row), sum / cnt, minf(v * 4.0, 1.0)))
