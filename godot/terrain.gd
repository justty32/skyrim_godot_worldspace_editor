class_name TerrainGrid
extends Node3D
## Editable terrain mesh based on a (verts_x × verts_y) height grid.
##
## Coordinate mapping (Skyrim ↔ Godot):
##   col 0 = west,  col (verts_x-1) = east
##   row 0 = south, row (verts_y-1) = north
##   Godot X = col × step  (east)
##   Godot Z = -row × step (north = -Z because Godot +Z is south)
##   Godot Y = (height - min_height) × METERS_PER_UNIT × vis_height_scale
##
## Heights stored in Skyrim game units (e.g. 4000–4500).
## step = 128 game_units × 0.014286 m/unit ≈ 1.83 m (vertex spacing).

const METERS_PER_UNIT := 0.014286
const VERT_STEP_UNITS := 128.0
const STEP := VERT_STEP_UNITS * METERS_PER_UNIT

# ── Configuration ────────────────────────────────────────────────────────────
var cells_x    := 3
var cells_y    := 2
var min_height := 4000.0
var max_height := 4500.0

# ── Derived ──────────────────────────────────────────────────────────────────
var verts_x: int
var verts_y: int
var step: float = STEP
var vis_height_scale   := 10.0  # vertical exaggeration for display only
var vis_surface_scale  := 1.0   # horizontal (X/Z) exaggeration for display only

# ── Height data ──────────────────────────────────────────────────────────────
var heights: PackedFloat32Array  # [row * verts_x + col], game units

# ── Splat overlay (display only) ───────────────────────────────────────────────
# The active splat layer's alpha grid + tint, pushed by SplatTool for visual feedback.
# Empty alpha = no overlay → mesh colors are pure height shading (behavior unchanged).
var splat_overlay_alpha: PackedFloat32Array = PackedFloat32Array()
var splat_overlay_color: Color = Color(0.30, 0.62, 0.25)

# ── Brush ─────────────────────────────────────────────────────────────────────
enum BrushMode { RAISE = 0, LOWER = 1, FLATTEN = 2, SMOOTH = 3 }
var brush_mode: int     = BrushMode.RAISE
var brush_radius        := 4.0
var brush_strength      := 50.0
var flatten_height      := 4000.0

var _mesh_inst: MeshInstance3D
var _shader_mat: ShaderMaterial   # WYSIWYG terrain blend material
var _collision: CollisionShape3D  # terrain walk collision (lazily refreshed)

# Persistent mesh arrays (owned here, filled by TerrainMeshBuilder) so a brush stroke updates only
# the touched region instead of reallocating + recomputing the whole grid every tick.
var _arr_mesh: ArrayMesh
var _m_verts: PackedVector3Array   = PackedVector3Array()
var _m_normals: PackedVector3Array = PackedVector3Array()
var _m_uvs: PackedVector2Array     = PackedVector2Array()
var _m_colors: PackedColorArray    = PackedColorArray()
var _m_indices: PackedInt32Array   = PackedInt32Array()

# Ground-texture tiling (how many times a 1024² LTEX repeats across the whole terrain).
var tex_uv_scale := 24.0

signal terrain_changed


func _ready() -> void:
	_mesh_inst = MeshInstance3D.new()
	# WYSIWYG terrain material: blends real LTEX ground textures by per-vertex alpha, falling back
	# to the height-gradient vertex colour until textures are pulled in (TerrainMaterial.apply).
	_shader_mat = TerrainMaterial.make()
	_mesh_inst.material_override = _shader_mat
	add_child(_mesh_inst)

	var body := StaticBody3D.new()
	add_child(body)
	_collision = CollisionShape3D.new()
	body.add_child(_collision)


func configure(cx: int, cy: int, min_h: float, max_h: float) -> void:
	cells_x = cx; cells_y = cy
	min_height = min_h; max_height = max_h
	verts_x = cells_x * 32 + 1
	verts_y = cells_y * 32 + 1
	heights = PackedFloat32Array()
	heights.resize(verts_x * verts_y)
	heights.fill((min_h + max_h) * 0.5)
	rebuild_mesh()


# Grow/shrink the grid to new_cx × new_cy cells, keeping the SW origin (col 0 / row 0) fixed so
# existing heights, placements and splatmaps stay coordinate-registered. New verts extend the
# nearest old edge value (flat continuation, no seam cliff). SplatTool.resize_grid must follow.
func resize_cells(new_cx: int, new_cy: int) -> void:
	var old_vx := verts_x
	var old_vy := verts_y
	var old := heights
	cells_x = maxi(1, new_cx)
	cells_y = maxi(1, new_cy)
	verts_x = cells_x * 32 + 1
	verts_y = cells_y * 32 + 1
	var nh := PackedFloat32Array()
	nh.resize(verts_x * verts_y)
	for r in verts_y:
		var orr := mini(r, old_vy - 1)
		for c in verts_x:
			var oc := mini(c, old_vx - 1)
			nh[r * verts_x + c] = old[orr * old_vx + oc]
	heights = nh
	splat_overlay_alpha = PackedFloat32Array()   # stale (old size) → drop; SplatTool repopulates
	rebuild_mesh()
	terrain_changed.emit()


# ── Accessors ────────────────────────────────────────────────────────────────

func get_height(col: int, row: int) -> float:
	return heights[row * verts_x + col]


func set_height(col: int, row: int, h: float) -> void:
	heights[row * verts_x + col] = clampf(h, min_height, max_height)


# Coordinate-system math lives in TerrainCoords (static); these forward to keep the call API stable
# (same delegation as rebuild_mesh → TerrainMeshBuilder). See terrain_coords.gd for the math.
func world_to_vert(world_pos: Vector3) -> Vector2i:
	return TerrainCoords.world_to_vert(self, world_pos)

func vert_to_world(col: int, row: int) -> Vector3:
	return TerrainCoords.vert_to_world(self, col, row)

func world_to_canonical_meters(display_world: Vector3) -> Vector3:
	return TerrainCoords.world_to_canonical_meters(self, display_world)

func canonical_meters_to_world(m: Vector3) -> Vector3:
	return TerrainCoords.canonical_meters_to_world(self, m)

func surface_display_y(display_world: Vector3) -> float:
	return TerrainCoords.surface_display_y(self, display_world)

func get_hit_position(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	return TerrainCoords.get_hit_position(self, camera, screen_pos)


# ── Brush / Mesh (delegated) ──────────────────────────────────────────────────

func apply_brush(hit_world: Vector3, delta: float) -> void:
	if TerrainBrush.apply(self, hit_world, delta):
		# Brush touched the vert box within ceil(brush_radius) of the hit centre (same bounds as
		# TerrainBrush.apply); update just that region instead of rebuilding the whole mesh.
		var cv := world_to_vert(hit_world)
		var r := int(ceilf(brush_radius))
		TerrainMeshBuilder.update_region(self, cv.x - r, cv.y - r, cv.x + r, cv.y + r)
		terrain_changed.emit()


func rebuild_mesh() -> void:
	TerrainMeshBuilder.build_full(self)
	_mesh_inst.mesh = _arr_mesh


# Update the WYSIWYG blend material. base_tex may be null; layers = Array of
# { "tex": Texture2D|null, "alpha": PackedFloat32Array } (one per splat layer).
func apply_textures(base_tex: Texture2D, layers: Array) -> void:
	if _shader_mat:
		TerrainMaterial.apply(_shader_mat, base_tex, layers, verts_x, verts_y, tex_uv_scale)


# Regenerate walk collision from the current mesh. Call before entering walk mode
# (skipped during editing so brush strokes stay cheap).
func refresh_collision() -> void:
	if _collision and _mesh_inst.mesh:
		_collision.shape = _mesh_inst.mesh.create_trimesh_shape()
