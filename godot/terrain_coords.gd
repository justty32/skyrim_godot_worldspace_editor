class_name TerrainCoords
## Pure coordinate-system math for TerrainGrid: Skyrim↔Godot↔display-world↔vertex conversions and
## camera ray picking. Split out of terrain.gd so the grid node keeps just height data + brush/mesh
## state; TerrainGrid forwards its public coord methods here (same static-helper pattern as
## TerrainMeshBuilder / TerrainBrush). All funcs take the grid `t` and read its scales/bounds.

const MPU := TerrainGrid.METERS_PER_UNIT


static func world_to_vert(t: TerrainGrid, world_pos: Vector3) -> Vector2i:
	var ds := t.step * t.vis_surface_scale
	return Vector2i(int(roundf(world_pos.x / ds)), int(roundf(-world_pos.z / ds)))


static func vert_to_world(t: TerrainGrid, col: int, row: int) -> Vector3:
	var ds := t.step * t.vis_surface_scale
	return Vector3(col * ds, (t.get_height(col, row) - t.min_height) * MPU * t.vis_height_scale, -row * ds)


# Display world pos → canonical Godot-native metres (display scales divided out). placements.json
# positions are these unscaled metres; ModForge converts to game units. Y: surface height h (game
# units) maps to canonical y = h × MPU, so ModForge's skyrim_z = y / MPU recovers h (sits on ground).
static func world_to_canonical_meters(t: TerrainGrid, display_world: Vector3) -> Vector3:
	return Vector3(
		display_world.x / t.vis_surface_scale,
		display_world.y / t.vis_height_scale + t.min_height * MPU,
		display_world.z / t.vis_surface_scale)


static func canonical_meters_to_world(t: TerrainGrid, m: Vector3) -> Vector3:
	return Vector3(
		m.x * t.vis_surface_scale,
		(m.y - t.min_height * MPU) * t.vis_height_scale,
		m.z * t.vis_surface_scale)


# Display-world Y of the terrain surface at the vertex nearest a clicked point (placement snaps here;
# get_hit_position returns the mid-plane Y, not the surface).
static func surface_display_y(t: TerrainGrid, display_world: Vector3) -> float:
	var vc := world_to_vert(t, display_world)
	var col := clampi(vc.x, 0, t.verts_x - 1)
	var row := clampi(vc.y, 0, t.verts_y - 1)
	return (t.get_height(col, row) - t.min_height) * MPU * t.vis_height_scale


# Display-world Y of the terrain surface under a world X/Z (bilinear over the height grid).
# Returns NAN when (x,z) is outside the grid footprint (no surface there).
static func surface_y_at(t: TerrainGrid, x: float, z: float) -> float:
	var ds := t.step * t.vis_surface_scale
	var fc := x / ds          # fractional column (east)
	var fr := -z / ds         # fractional row (north)
	if fc < 0.0 or fc > t.verts_x - 1 or fr < 0.0 or fr > t.verts_y - 1:
		return NAN
	var c0 := int(floor(fc)); var c1 := mini(c0 + 1, t.verts_x - 1)
	var r0 := int(floor(fr)); var r1 := mini(r0 + 1, t.verts_y - 1)
	var tx := fc - c0; var tz := fr - r0
	var h0 := lerpf(t.get_height(c0, r0), t.get_height(c1, r0), tx)
	var h1 := lerpf(t.get_height(c0, r1), t.get_height(c1, r1), tx)
	return (lerpf(h0, h1, tz) - t.min_height) * MPU * t.vis_height_scale


# Ray from screen → the terrain SURFACE (raymarched over the height grid), so raised ground
# correctly blocks the ray. Returns ZERO when the ray misses the grid footprint / surface.
static func get_hit_position(t: TerrainGrid, camera: Camera3D, screen_pos: Vector2) -> Vector3:
	if camera == null: return Vector3.ZERO
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	var ds   := t.step * t.vis_surface_scale
	var maxx := (t.verts_x - 1) * ds
	var minz := -(t.verts_y - 1) * ds
	# Clip the ray to the grid's X/Z footprint (slab test) so we only march inside it.
	var t0 := 0.0
	var t1 := 1.0e9
	var rng = _slab(from.x, dir.x, 0.0, maxx)
	if rng == null: return Vector3.ZERO
	t0 = maxf(t0, rng.x); t1 = minf(t1, rng.y)
	rng = _slab(from.z, dir.z, minz, 0.0)
	if rng == null: return Vector3.ZERO
	t0 = maxf(t0, rng.x); t1 = minf(t1, rng.y)
	if t0 > t1: return Vector3.ZERO
	# March entry→exit; detect where the ray drops to/below the surface, then bisect.
	var step_t := ds * 0.5
	var iters := mini(int((t1 - t0) / step_t) + 2, 4096)
	var prev_t := t0
	for i in iters:
		var ct := minf(t0 + i * step_t, t1)
		var p := from + dir * ct
		var sy := surface_y_at(t, p.x, p.z)
		if not (is_nan(sy) or p.y >= sy):
			if i == 0: return Vector3.ZERO   # camera already under the surface
			var lo := prev_t; var hi := ct
			for k in 16:
				var mid := (lo + hi) * 0.5
				var sm := surface_y_at(t, (from + dir * mid).x, (from + dir * mid).z)
				if is_nan(sm) or (from + dir * mid).y >= sm: lo = mid
				else: hi = mid
			var hit := from + dir * hi
			hit.x = clampf(hit.x, 0.0, maxx)
			hit.z = clampf(hit.z, minz, 0.0)
			return hit
		prev_t = ct
	return Vector3.ZERO


# [t_enter, t_exit] (Vector2) where `o + d*t` stays within [lo, hi] on one axis; null if never.
static func _slab(o: float, d: float, lo: float, hi: float):
	if absf(d) < 1.0e-9:
		return null if (o < lo or o > hi) else Vector2(-1.0e9, 1.0e9)
	var ta := (lo - o) / d
	var tb := (hi - o) / d
	return Vector2(minf(ta, tb), maxf(ta, tb))
