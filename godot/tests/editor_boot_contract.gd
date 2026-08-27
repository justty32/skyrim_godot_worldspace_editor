extends SceneTree
## Headless probe for tests/test_editor_boot.py. Boots the real root scene (res://main.tscn) and
## reports what its _ready wiring actually produced: the terrain, the camera rig, the four tool
## nodes, the cursor, the grid outlines, the side panel's collapsible sections, and the two status
## labels the panel hands back. Nothing else exercises that wiring offline — a mis-ordered or
## dropped line in the scene assembly would otherwise only surface when a human opens the GUI.
## Also pins the Place/Splat mutual exclusion, which lives in two separate toggle functions.
## Runs only in that harness's temporary project copy.

const MAIN_SCENE := "res://main.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _section_titles(node: Node, out: Array) -> void:
	# UiSection.make() marks each collapsible group with a toggle Button captioned "▼ <title>".
	if node is Button and node.toggle_mode and node.text.begins_with("▼ "):
		out.append(node.text.substr(2))
	for child in node.get_children():
		_section_titles(child, out)


func _grid_dims_label(node: Node) -> String:
	# GridUi keeps a live "N×M cells  (V×W verts)" readout wired to terrain_changed.
	if node is Label and node.text.ends_with(" verts)"):
		return node.text
	for child in node.get_children():
		var found := _grid_dims_label(child)
		if found != "":
			return found
	return ""


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("usage: editor_boot_contract.gd -- <result.json>")
		quit(2)
		return

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		push_error("cannot load " + MAIN_SCENE)
		quit(3)
		return
	var editor: WorldspaceEditor = packed.instantiate()
	root.add_child(editor)

	var sections: Array = []
	_section_titles(editor, sections)

	var result := {
		"cells": [editor.terrain.cells_x, editor.terrain.cells_y],
		"verts": [editor.terrain.verts_x, editor.terrain.verts_y],
		"height_range": [editor.terrain.min_height, editor.terrain.max_height],
		"has_camera": editor.camera_rig != null and editor.camera_rig.get_camera() is Camera3D,
		"tools_in_tree": {
			"terrain": editor.terrain != null and editor.terrain.is_inside_tree(),
			"placement": editor._placement != null and editor._placement.is_inside_tree(),
			"splat": editor._splat != null and editor._splat.is_inside_tree(),
			"model_fetch": editor._model_fetch != null and editor._model_fetch.is_inside_tree(),
			"tex_fetch": editor._tex_fetch != null and editor._tex_fetch.is_inside_tree(),
		},
		"cursor_present": editor._cursor != null and editor._cursor.is_inside_tree(),
		"cursor_hidden_at_boot": editor._cursor != null and not editor._cursor.visible,
		"grid_lines": editor._grid_lines.size(),
		"labels_wired": editor._lbl_pos != null and editor._lbl_brush != null,
		"panel_sections": sections,
		"splat_layers": editor._splat.count(),
		"splat_active": editor._splat.active,
		"splat_base_texture": editor._splat.base_texture,
		"modes_at_boot": [editor._place_mode, editor._splat_mode, editor._painting],
	}

	# Place and Splat are mutually exclusive; each toggle also has to drop any in-progress stroke.
	editor._painting = true
	editor._toggle_place_mode(true)
	result["after_place_on"] = [editor._place_mode, editor._splat_mode, editor._painting]
	editor._painting = true
	editor._toggle_splat_mode(true)
	result["after_splat_on"] = [editor._place_mode, editor._splat_mode, editor._painting]

	# Growing the worldspace must keep terrain and splat grids the same size, or every layer's
	# alpha silently desynchronises from the heightmap it co-registers with.
	editor._add_cells(1, 1)
	result["after_grow"] = {
		"cells": [editor.terrain.cells_x, editor.terrain.cells_y],
		"verts": [editor.terrain.verts_x, editor.terrain.verts_y],
		"splat_alpha_size": editor._splat.layers[editor._splat.active]["alpha"].size(),
		"grid_lines": editor._grid_lines.size(),
		"grid_dims_label": _grid_dims_label(editor),
	}

	var out := FileAccess.open(args[0], FileAccess.WRITE)
	if out == null:
		push_error("cannot write editor boot result: " + args[0])
		quit(4)
		return
	out.store_string(JSON.stringify(result))
	out.close()
	quit()
