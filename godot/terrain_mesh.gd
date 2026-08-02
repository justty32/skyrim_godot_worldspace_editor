class_name TerrainMeshBuilder
## Builds the terrain ArrayMesh into persistent arrays owned by the TerrainGrid, so a brush stroke
## can recompute just the touched region (update_region) instead of regenerating the whole grid
## (build_full) every tick. Output is identical either way — update_region(full grid) == build_full.

# Full (re)build: (re)size the persistent arrays, fill every vertex + normal + index, upload. Used on
# configure/resize and whenever the whole grid changes (e.g. splat-overlay colour swap).
static func build_full(t: TerrainGrid) -> void:
	var n := t.verts_x * t.verts_y
	if t._m_verts.size() != n:
		t._m_verts = PackedVector3Array();   t._m_verts.resize(n)
		t._m_normals = PackedVector3Array(); t._m_normals.resize(n)
		t._m_uvs = PackedVector2Array();     t._m_uvs.resize(n)
		t._m_colors = PackedColorArray();    t._m_colors.resize(n)
	for row in t.verts_y:
		for col in t.verts_x:
			_set_vertex(t, col, row)
	for row in t.verts_y:
		for col in t.verts_x:
			_set_normal(t, col, row)
	_build_indices(t)
	_upload(t)


# Incremental update of the vertex box [c0..c1]×[r0..r1] (inclusive). Vertices/UV/colour are
# recomputed in that box; normals over the box expanded by 1 on each side (they read neighbours).
static func update_region(t: TerrainGrid, c0: int, r0: int, c1: int, r1: int) -> void:
	if t._m_verts.size() != t.verts_x * t.verts_y:
		build_full(t); return   # arrays stale (size changed) → fall back to a full build
	c0 = maxi(c0, 0); r0 = maxi(r0, 0)
	c1 = mini(c1, t.verts_x - 1); r1 = mini(r1, t.verts_y - 1)
	for row in range(r0, r1 + 1):
		for col in range(c0, c1 + 1):
			_set_vertex(t, col, row)
	var nc0 := maxi(c0 - 1, 0); var nr0 := maxi(r0 - 1, 0)
	var nc1 := mini(c1 + 1, t.verts_x - 1); var nr1 := mini(r1 + 1, t.verts_y - 1)
	for row in range(nr0, nr1 + 1):
		for col in range(nc0, nc1 + 1):
			_set_normal(t, col, row)
	_upload(t)


# ── per-element compute (shared by full + incremental paths) ──────────────────

static func _set_vertex(t: TerrainGrid, col: int, row: int) -> void:
	var ds := t.step * t.vis_surface_scale
	var inv_rng := 1.0 / maxf(t.max_height - t.min_height, 1.0)
	var has_splat := t.splat_overlay_alpha.size() == t.verts_x * t.verts_y
	var idx := row * t.verts_x + col
	var h := t.get_height(col, row)
	# Y = (h - min_height) * MPU * vis_height_scale  → terrain floor sits at Y=0
	t._m_verts[idx] = Vector3(
		col * ds,
		(h - t.min_height) * TerrainGrid.METERS_PER_UNIT * t.vis_height_scale,
		-row * ds)
	t._m_uvs[idx] = Vector2(float(col) / (t.verts_x - 1), float(row) / (t.verts_y - 1))
	var c := _height_color(clampf((h - t.min_height) * inv_rng, 0.0, 1.0))
	if has_splat:
		var a := t.splat_overlay_alpha[idx]
		if a > 0.0:
			c = c.lerp(t.splat_overlay_color, clampf(a, 0.0, 1.0))
	t._m_colors[idx] = c


static func _set_normal(t: TerrainGrid, col: int, row: int) -> void:
	var ds := t.step * t.vis_surface_scale
	var he := _h(t, col + 1, row); var hw := _h(t, col - 1, row)
	var hn := _h(t, col, row + 1); var hs := _h(t, col, row - 1)
	var dh_east  := (he - hw) * TerrainGrid.METERS_PER_UNIT * t.vis_height_scale / (2.0 * ds)
	var dh_north := (hn - hs) * TerrainGrid.METERS_PER_UNIT * t.vis_height_scale / (2.0 * ds)
	t._m_normals[row * t.verts_x + col] = Vector3(-dh_east, 1.0, dh_north).normalized()


static func _build_indices(t: TerrainGrid) -> void:
	var ni := (t.verts_x - 1) * (t.verts_y - 1) * 6
	if t._m_indices.size() != ni:
		t._m_indices = PackedInt32Array(); t._m_indices.resize(ni)
	var qi := 0
	for row in (t.verts_y - 1):
		for col in (t.verts_x - 1):
			var base := row * t.verts_x + col
			t._m_indices[qi] = base;                 qi += 1
			t._m_indices[qi] = base + t.verts_x;     qi += 1
			t._m_indices[qi] = base + 1;             qi += 1
			t._m_indices[qi] = base + 1;             qi += 1
			t._m_indices[qi] = base + t.verts_x;     qi += 1
			t._m_indices[qi] = base + t.verts_x + 1; qi += 1


static func _upload(t: TerrainGrid) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t._m_verts
	arrays[Mesh.ARRAY_NORMAL] = t._m_normals
	arrays[Mesh.ARRAY_TEX_UV] = t._m_uvs
	arrays[Mesh.ARRAY_COLOR]  = t._m_colors
	arrays[Mesh.ARRAY_INDEX]  = t._m_indices
	if t._arr_mesh == null:
		t._arr_mesh = ArrayMesh.new()
	t._arr_mesh.clear_surfaces()
	t._arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _h(t: TerrainGrid, col: int, row: int) -> float:
	return t.get_height(clampi(col, 0, t.verts_x - 1), clampi(row, 0, t.verts_y - 1))


# Normalized height [0,1] → terrain gradient, with the mid-height (0.5) baseline
# as the land/water divide: below it sinks through water → deep blue, above it
# rises through grass → rock → snow.
static func _height_color(nt: float) -> Color:
	var deep  := Color(0.05, 0.10, 0.30)  # deep water
	var water := Color(0.15, 0.35, 0.60)  # shallow water
	var grass := Color(0.40, 0.52, 0.24)  # baseline ground
	var rock  := Color(0.45, 0.38, 0.30)  # exposed rock
	var snow  := Color(0.95, 0.95, 0.97)  # snow cap
	if nt < 0.5:
		if nt < 0.25:
			return deep.lerp(water, nt / 0.25)
		return water.lerp(grass, (nt - 0.25) / 0.25)
	if nt < 0.8:
		return grass.lerp(rock, (nt - 0.5) / 0.3)
	return rock.lerp(snow, (nt - 0.8) / 0.2)
