class_name WorldspaceEditor
extends Node3D
## WorldspaceEditor — root scene.
##
## Adjust these constants before starting:
##   CELLS_X, CELLS_Y   — number of Skyrim cells
##   MIN_HEIGHT, MAX_HEIGHT — Skyrim game units (e.g. 4000–4500)
##
## Controls:
##   Left-click drag   — paint with current brush
##   WASD              — pan the camera on the ground plane
##   Middle-click drag — orbit camera
##   Scroll            — zoom   (Shift+Scroll — scroll the side panel)
##   Right-click drag  — pan
##   Brush mode (Raise / Lower / Flatten / Smooth) is chosen from the side panel

const CELLS_X    := 3
const CELLS_Y    := 2
const MIN_HEIGHT := 4000.0
const MAX_HEIGHT := 4500.0

var terrain:    TerrainGrid
var camera_rig: CameraRig

var _lbl_pos:   Label
var _lbl_brush: Label
var _cursor:    MeshInstance3D
var _painting   := false
var _ui_width   := 200
var _grid_lines: Array[Node3D] = []
var _player: PlayerController = null
var _placement: PlacementTool = null
var _model_fetch: ModelFetch = null
var _place_mode := false
var _splat: SplatTool = null
var _tex_fetch: TexFetch = null
var _splat_mode := false


func _ready() -> void:
	SceneBuilder.environment(self)
	terrain = TerrainGrid.new()
	add_child(terrain)
	terrain.configure(CELLS_X, CELLS_Y, MIN_HEIGHT, MAX_HEIGHT)
	camera_rig  = SceneBuilder.camera(self, terrain)
	_cursor     = SceneBuilder.cursor(self)
	_grid_lines = SceneBuilder.grid_outlines(self, terrain.cells_x, terrain.cells_y, terrain)
	_model_fetch = ModelFetch.new()
	add_child(_model_fetch)
	_placement  = PlacementTool.new()
	add_child(_placement)
	_placement.configure(terrain, _model_fetch)
	_tex_fetch  = TexFetch.new()
	add_child(_tex_fetch)
	_splat      = SplatTool.new()
	add_child(_splat)
	_splat.configure(terrain, _tex_fetch)
	_setup_ui()


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := WorldUI.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE)
	canvas.add_child(panel)
	panel.setup(terrain, _ui_width, _update_cursor, _sync_display,
		_on_export_png, _on_import_png, _enter_walk_mode)
	PlacementUi.build(panel.content_vbox(), _placement,
		_toggle_place_mode, _on_export_placements, _on_import_placements)
	SplatUi.build(panel.content_vbox(), _splat,
		_toggle_splat_mode, _on_export_splat, _on_import_splat, _update_cursor)
	GridUi.build(panel.content_vbox(), terrain, _add_cells)
	_lbl_pos   = panel.lbl_pos
	_lbl_brush = panel.lbl_brush

	var bottom := Label.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.add_theme_color_override("font_color", Color.WHITE)
	bottom.text = "WASD: move  |  Middle-drag: orbit  |  Scroll: zoom  |  Right-drag: pan  |  LMB: paint  |  Shift+Scroll: panel"
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(bottom)


# Syncs camera and grid after any display-scale change (height or surface).
func _sync_display() -> void:
	var ds := terrain.step * terrain.vis_surface_scale
	var cx := (terrain.verts_x - 1) * ds * 0.5
	var cz := -(terrain.verts_y - 1) * ds * 0.5
	var cy := (terrain.max_height - terrain.min_height) * 0.5 \
		* TerrainGrid.METERS_PER_UNIT * terrain.vis_height_scale
	camera_rig.target = Vector3(cx, cy, cz)
	camera_rig.refresh()
	_rebuild_grid_lines()
	_update_cursor()


func _rebuild_grid_lines() -> void:
	for mesh in _grid_lines:
		mesh.queue_free()
	_grid_lines = SceneBuilder.grid_outlines(self, terrain.cells_x, terrain.cells_y, terrain)


# Grow/shrink the worldspace by (de, dn) cells on East / North. Capture old vert dims first so
# the splat layers can be remapped, then resize terrain, grid lines and camera. SW origin stays
# fixed, so placements keep their coordinates.
func _add_cells(de: int, dn: int) -> void:
	var ncx := maxi(1, terrain.cells_x + de)
	var ncy := maxi(1, terrain.cells_y + dn)
	if ncx == terrain.cells_x and ncy == terrain.cells_y:
		return
	var old_vx := terrain.verts_x
	var old_vy := terrain.verts_y
	terrain.resize_cells(ncx, ncy)
	_splat.resize_grid(old_vx, old_vy)
	_sync_display()   # rebuilds grid lines itself, so no separate _rebuild_grid_lines() here


# ── Walk mode / Input (delegated) ───────────────────────────────────────────────
# Walk-mode lifecycle lives in WalkMode; input routing + per-frame cursor/paint in EditorInput.

func _enter_walk_mode() -> void: WalkMode.enter(self)
func _exit_walk_mode() -> void:  WalkMode.exit(self)

func _input(event: InputEvent) -> void: EditorInput.input(self, event)
func _process(delta: float) -> void:    EditorInput.process(self, delta)

func _update_cursor() -> void:
	# Cursor disc tracks the ACTIVE tool's radius so the yellow ring matches what LMB affects:
	#   Place Mode — a tiny ring (placement hits a point, not an area);
	#   Splat Mode — the splat paint radius;
	#   else       — the height-brush radius.
	var verts_r := terrain.brush_radius
	if _place_mode:
		verts_r = 0.5
	elif _splat_mode and _splat:
		verts_r = _splat.radius
	var r := verts_r * terrain.step * terrain.vis_surface_scale
	_cursor.scale = Vector3(r, 1.0, r)


# ── Export / Import ───────────────────────────────────────────────────────────

func _on_export_png() -> void:
	IoPng.export_dialog(self, terrain, _lbl_brush)

func _on_import_png() -> void:
	IoPng.import_dialog(self, terrain)


# ── Placement ───────────────────────────────────────────────────────────────────

# In place mode LMB drops objects instead of painting; brush painting is suspended.
# Place and Splat are mutually exclusive — turning one on clears the other's flag.
func _toggle_place_mode(on: bool) -> void:
	_place_mode = on
	if on: _splat_mode = false
	_painting = false
	_update_cursor()   # tiny ring in place mode (or back to brush/splat radius)

func _on_export_placements() -> void:
	PlacementsIo.export_dialog(self, _placement, terrain, _lbl_brush)

func _on_import_placements() -> void:
	PlacementsIo.import_dialog(self, _placement, terrain, _lbl_brush)


# ── Splat (texture alpha) ───────────────────────────────────────────────────────

# In splat mode LMB paints the active texture layer's alpha (instead of the height brush).
func _toggle_splat_mode(on: bool) -> void:
	_splat_mode = on
	if on: _place_mode = false
	_painting = false
	_update_cursor()   # ring resizes to the splat radius (or back to brush radius)

func _on_export_splat() -> void:
	SplatmapIo.export_dialog(self, _splat, terrain, _lbl_brush)

func _on_import_splat() -> void:
	SplatmapIo.import_dialog(self, _splat, terrain, _lbl_brush)
