class_name EditorSetup
## Scene assembly for WorldspaceEditor: the environment, terrain, camera rig, cursor and grid
## outlines, the four tool nodes, and the side panel stitched together from the four UI modules.
## Split out of main.gd — same static-helper pattern as SceneBuilder / EditorInput / WalkMode — so
## the root script keeps only its constants, its display/mode state and its export hooks.
##
## The ORDER here is load-bearing and is what tests/test_editor_boot.py pins: the terrain must exist
## before the camera rig frames it, both tool pairs must exist before `panel()` hands their bound
## callbacks to the UI modules, and the panel must be built before its two status labels come back.

static func build(m: WorldspaceEditor) -> void:
	SceneBuilder.environment(m)
	m.terrain = TerrainGrid.new()
	m.add_child(m.terrain)
	m.terrain.configure(WorldspaceEditor.CELLS_X, WorldspaceEditor.CELLS_Y,
		WorldspaceEditor.MIN_HEIGHT, WorldspaceEditor.MAX_HEIGHT)
	m.camera_rig  = SceneBuilder.camera(m, m.terrain)
	m._cursor     = SceneBuilder.cursor(m)
	m._grid_lines = SceneBuilder.grid_outlines(m, m.terrain.cells_x, m.terrain.cells_y, m.terrain)
	m._model_fetch = ModelFetch.new()
	m.add_child(m._model_fetch)
	m._placement  = PlacementTool.new()
	m.add_child(m._placement)
	m._placement.configure(m.terrain, m._model_fetch)
	m._tex_fetch  = TexFetch.new()
	m.add_child(m._tex_fetch)
	m._splat      = SplatTool.new()
	m.add_child(m._splat)
	m._splat.configure(m.terrain, m._tex_fetch)
	panel(m)


# The side panel (WorldUI) plus the three module sections appended into its content column, and the
# fixed controls hint across the bottom of the screen.
static func panel(m: WorldspaceEditor) -> void:
	var canvas := CanvasLayer.new()
	m.add_child(canvas)

	var panel_ui := WorldUI.new()
	panel_ui.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE)
	canvas.add_child(panel_ui)
	panel_ui.setup(m.terrain, m._ui_width, m._update_cursor, m._sync_display,
		m._on_export_png, m._on_import_png, m._enter_walk_mode)
	PlacementUi.build(panel_ui.content_vbox(), m._placement,
		m._toggle_place_mode, m._on_export_placements, m._on_import_placements)
	SplatUi.build(panel_ui.content_vbox(), m._splat,
		m._toggle_splat_mode, m._on_export_splat, m._on_import_splat, m._update_cursor)
	GridUi.build(panel_ui.content_vbox(), m.terrain, m._add_cells)
	m._lbl_pos   = panel_ui.lbl_pos
	m._lbl_brush = panel_ui.lbl_brush

	var bottom := Label.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.add_theme_color_override("font_color", Color.WHITE)
	bottom.text = "WASD: move  |  Middle-drag: orbit  |  Scroll: zoom  |  Right-drag: pan  |  LMB: paint  |  Shift+Scroll: panel"
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(bottom)
