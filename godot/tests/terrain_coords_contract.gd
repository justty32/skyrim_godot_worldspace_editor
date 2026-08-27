extends SceneTree
## Headless probe for tests/test_terrain_coords.py. Exercises TerrainCoords.raycast_surface — the
## cursor/click picking that every editor mode goes through — on a real TerrainGrid, without a
## Camera3D. get_hit_position only turns a screen position into (origin, direction); the marching,
## the footprint clipping and the "no hit" cases all live in raycast_surface, so that is what is
## pinned here. Runs only in that harness's temporary project copy.

const CELLS := 1                     # 1×1 cell → 33×33 verts
const MIN_H := 0.0
const MAX_H := 1000.0
const FLAT_H := 500.0
const RIDGE_H := 1000.0
const RIDGE_COL_LO := 4
const RIDGE_COL_HI := 8
const PROBE_Z := -10.0
const RIDGE_RAY_Y := 100.0           # above the flat ground, below the ridge top
const SIDE_ENTRY_Y := 30.0           # below the flat ground → ray enters the terrain side-on


func _initialize() -> void:
	call_deferred("_run")


func _v(p: Vector3) -> Array:
	return [p.x, p.y, p.z]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: terrain_coords_contract.gd -- <result.json>")
		quit(2)
		return

	var terrain := TerrainGrid.new()
	root.add_child(terrain)
	terrain.configure(CELLS, CELLS, MIN_H, MAX_H)
	for row in terrain.verts_y:
		for col in terrain.verts_x:
			terrain.set_height(col, row, FLAT_H)

	var ds: float = terrain.step * terrain.vis_surface_scale
	var flat_y: float = (FLAT_H - MIN_H) * TerrainGrid.METERS_PER_UNIT * terrain.vis_height_scale
	var inside_x: float = 10.0

	var result := {
		"ds": ds,
		"flat_surface_y": flat_y,
		"max_x": (terrain.verts_x - 1) * ds,
		# Straight down from above the middle of the grid: the ordinary picking case.
		"down_from_above": _v(TerrainCoords.raycast_surface(
			terrain, Vector3(inside_x, 200.0, PROBE_Z), Vector3(0.0, -1.0, 0.0))),
		# Never enters the X/Z footprint → miss.
		"outside_footprint": _v(TerrainCoords.raycast_surface(
			terrain, Vector3(-40.0, 200.0, PROBE_Z), Vector3(0.0, -1.0, 0.0))),
		# Origin INSIDE the footprint and already under the surface → still a miss (unchanged).
		"origin_under_surface": _v(TerrainCoords.raycast_surface(
			terrain, Vector3(inside_x, 5.0, PROBE_Z), Vector3(0.0, -1.0, 0.0))),
		# The regression: origin OUTSIDE the footprint, ray horizontal and below the ground, so the
		# very first sample (the footprint entry point) is already under the surface. The entry
		# point is the hit; this used to return ZERO and make the cursor vanish on cliff walls.
		"side_entry_below_surface": _v(TerrainCoords.raycast_surface(
			terrain, Vector3(-20.0, SIDE_ENTRY_Y, PROBE_Z), Vector3(1.0, 0.0, 0.0))),
	}

	# Raised ground has to block a horizontal ray that passes over the flat part.
	for row in terrain.verts_y:
		for col in range(RIDGE_COL_LO, RIDGE_COL_HI + 1):
			terrain.set_height(col, row, RIDGE_H)
	result["ridge_hit"] = _v(TerrainCoords.raycast_surface(
		terrain, Vector3(2.0 * ds, RIDGE_RAY_Y, PROBE_Z), Vector3(1.0, 0.0, 0.0)))
	result["ridge_x_lo"] = (RIDGE_COL_LO - 1) * ds
	result["ridge_x_hi"] = RIDGE_COL_LO * ds
	result["ridge_ray_y"] = RIDGE_RAY_Y

	var out := FileAccess.open(args[0], FileAccess.WRITE)
	if out == null:
		push_error("cannot write terrain coords result: " + args[0])
		quit(3)
		return
	out.store_string(JSON.stringify(result))
	out.close()
	quit()
