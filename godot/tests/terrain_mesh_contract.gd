extends SceneTree
## Headless probe for tests/test_terrain_mesh.py. Covers the height brush and the incremental mesh
## update — the path that produces the editor's PRIMARY output (the heightmap ModForge turns into
## LAND/VHGT) and the one every brush tick runs through.
##
## terrain_mesh.gd claims in its own header that "update_region(full grid) == build_full". That is
## the whole justification for the incremental path existing, and nothing checked it. Verified to
## actually bite: shrinking the recomputed vertex box, shifting the normal box, or dropping the
## _upload() call each turn this red, naming the array that drifted.
##
## What it does NOT cover, and why: update_region's `-1 / +1` expansion of the normal box is dead
## weight for its only caller. TerrainBrush.apply moves a vertex only where dist < brush_radius, so
## the vertices that actually change sit within ±(ceil(radius) - 1), and the normals they disturb
## therefore sit within ±ceil(radius) — which is the un-expanded vertex box. Removing the expansion
## entirely leaves every assertion here green because the OUTPUT genuinely does not change. Keep the
## expansion (it is the correct general contract for the function), but do not read these tests as
## evidence that it is load-bearing.
## Runs only in that harness's temporary project copy.

const CELLS := 2
const MIN_H := 4000.0
const MAX_H := 4500.0
const BASE_H := 4200.0
const WAVE := 150.0
const DELTA := 0.1


func _initialize() -> void:
	call_deferred("_run")


func _reset_heights(t: TerrainGrid) -> void:
	# A non-flat field, so normals are non-trivial everywhere and a stale one actually shows up.
	for row in t.verts_y:
		for col in t.verts_x:
			t.set_height(col, row, BASE_H + WAVE * sin(col * 0.4) * cos(row * 0.3))
	t.rebuild_mesh()


func _snapshot(t: TerrainGrid) -> Dictionary:
	# Read back the UPLOADED surface, not the persistent _m_* arrays. Those two are only equal if
	# the path under test actually called _upload(); comparing the source arrays would happily pass
	# an incremental path that recomputed everything and then forgot to hand it to the mesh.
	var arrays: Array = t._arr_mesh.surface_get_arrays(0)
	return {
		"verts": arrays[Mesh.ARRAY_VERTEX],
		"normals": arrays[Mesh.ARRAY_NORMAL],
		"uvs": arrays[Mesh.ARRAY_TEX_UV],
		"colors": arrays[Mesh.ARRAY_COLOR],
		"indices": arrays[Mesh.ARRAY_INDEX],
	}


func _mismatches(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for key in a:
		var left = a[key]
		var right = b[key]
		if left.size() != right.size():
			out[key] = -1
			continue
		var bad := 0
		for i in left.size():
			if left[i] != right[i]:
				bad += 1
		out[key] = bad
	return out


# One stroke through the production path (apply_brush → update_region), compared against a full
# rebuild of the very same heights.
func _stroke_vs_full(t: TerrainGrid, mode: int, col: int, row: int) -> Dictionary:
	_reset_heights(t)
	t.brush_mode = mode
	t.apply_brush(t.vert_to_world(col, row), DELTA)
	var incremental := _snapshot(t)
	t.rebuild_mesh()
	return _mismatches(incremental, _snapshot(t))


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: terrain_mesh_contract.gd -- <result.json>")
		quit(2)
		return

	var t := TerrainGrid.new()
	root.add_child(t)
	t.configure(CELLS, CELLS, MIN_H, MAX_H)
	t.brush_radius = 4.0
	t.brush_strength = 50.0
	t.flatten_height = 4300.0

	var mid_col: int = t.verts_x / 2
	var mid_row: int = t.verts_y / 2
	var result := {
		"verts": [t.verts_x, t.verts_y],
		# Middle of the grid, and the SW corner where every neighbour lookup clamps.
		"raise_middle": _stroke_vs_full(t, TerrainGrid.BrushMode.RAISE, mid_col, mid_row),
		"raise_corner": _stroke_vs_full(t, TerrainGrid.BrushMode.RAISE, 0, 0),
		"lower_middle": _stroke_vs_full(t, TerrainGrid.BrushMode.LOWER, mid_col, mid_row),
		"flatten_middle": _stroke_vs_full(t, TerrainGrid.BrushMode.FLATTEN, mid_col, mid_row),
		"smooth_middle": _stroke_vs_full(t, TerrainGrid.BrushMode.SMOOTH, mid_col, mid_row),
	}

	# What RAISE actually does to the height field: strongest at the centre, tapering to nothing at
	# the radius, and strictly nothing beyond it.
	_reset_heights(t)
	t.brush_mode = TerrainGrid.BrushMode.RAISE
	var before := t.heights.duplicate()
	t.apply_brush(t.vert_to_world(mid_col, mid_row), DELTA)
	var idx := func(c: int, r: int) -> int: return r * t.verts_x + c
	var outside_touched := 0
	var inside_raised := 0
	for row in t.verts_y:
		for col in t.verts_x:
			var i: int = idx.call(col, row)
			var dist := Vector2(col - mid_col, row - mid_row).length()
			if dist > t.brush_radius:
				if t.heights[i] != before[i]:
					outside_touched += 1
			elif t.heights[i] > before[i]:
				inside_raised += 1
	result["raise_profile"] = {
		"centre_gain": t.heights[idx.call(mid_col, mid_row)] - before[idx.call(mid_col, mid_row)],
		"edge_gain": t.heights[idx.call(mid_col + 4, mid_row)] - before[idx.call(mid_col + 4, mid_row)],
		"mid_gain": t.heights[idx.call(mid_col + 2, mid_row)] - before[idx.call(mid_col + 2, mid_row)],
		"outside_touched": outside_touched,
		"inside_raised": inside_raised,
	}

	# set_height clamps into [min_height, max_height]; a long RAISE must saturate, never overshoot
	# (an out-of-range height would encode into VHGT as garbage on the ModForge side).
	_reset_heights(t)
	for _i in 200:
		t.apply_brush(t.vert_to_world(mid_col, mid_row), DELTA)
	var over := 0
	var under := 0
	for h in t.heights:
		if h > MAX_H: over += 1
		if h < MIN_H: under += 1
	result["clamping"] = {
		"over_max": over,
		"under_min": under,
		"centre": t.heights[idx.call(mid_col, mid_row)],
		"max_height": MAX_H,
	}

	var out := FileAccess.open(args[0], FileAccess.WRITE)
	if out == null:
		push_error("cannot write terrain mesh result: " + args[0])
		quit(3)
		return
	out.store_string(JSON.stringify(result))
	out.close()
	quit()
