extends SceneTree
## Headless probe for tests/test_splat_contract.py. Covers the splat side of the editor:
##   * SplatmapIo save/load — the 8-bit grayscale PNG that feeds ModForge textureLayers[].splatmap,
##     including its north-on-top row convention and its size-mismatch refusal;
##   * SplatTool.set_active with no layers (the -1 trap a future "delete layer" button would hit);
##   * SplatUi.sync_layer_controls — must be idempotent, because SplatTool.paint() emits `changed`
##     on every tick of a held brush and this runs on that signal.
## Runs only in that harness's temporary project copy.

const CELLS := 1                     # 1×1 cell → 33×33 verts
const MIN_H := 0.0
const MAX_H := 1000.0
const SW_ALPHA := 1.0                # col 0, row 0     — south-west
const NW_ALPHA := 128.0 / 255.0      # col 0, row max   — north-west
const MID_ROW := 3
const MID_COL := 5
const MID_ALPHA := 64.0 / 255.0
const HALF_TYPED := "Skyrim.esm:0x01"
const ADDED_LAYER := "Skyrim.esm:0x000C16"
const SYNC_TICKS := 30               # stand-in for a held brush stroke


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("usage: splat_contract.gd -- <splat.png> <result.json>")
		quit(2)
		return
	var png_path: String = args[0]
	var result_path: String = args[1]

	var terrain := TerrainGrid.new()
	root.add_child(terrain)
	terrain.configure(CELLS, CELLS, MIN_H, MAX_H)
	var vx: int = terrain.verts_x
	var vy: int = terrain.verts_y

	var splat := SplatTool.new()
	root.add_child(splat)
	splat.configure(terrain, null)          # no TexFetch → tint fallback path, no CLI

	var result := {"verts_x": vx, "verts_y": vy}
	_probe_splatmap_io(result, terrain, png_path, vx, vy)
	_probe_empty_layers(result, terrain)
	_probe_ui_sync(result, splat)

	var out := FileAccess.open(result_path, FileAccess.WRITE)
	if out == null:
		push_error("cannot write splat contract result: " + result_path)
		quit(3)
		return
	out.store_string(JSON.stringify(result))
	out.close()
	quit()


func _probe_splatmap_io(result: Dictionary, terrain: TerrainGrid, png_path: String,
		vx: int, vy: int) -> void:
	var alpha := PackedFloat32Array()
	alpha.resize(vx * vy)
	alpha.fill(0.0)
	alpha[0 * vx + 0] = SW_ALPHA
	alpha[(vy - 1) * vx + 0] = NW_ALPHA
	alpha[MID_ROW * vx + MID_COL] = MID_ALPHA

	result["saved"] = SplatmapIo.save_png(png_path, terrain, alpha)
	var back := SplatmapIo.load_alpha(png_path, terrain)
	result["round_trip"] = {
		"size": back.size(),
		"sw": back[0 * vx + 0] if back.size() == vx * vy else -1.0,
		"nw": back[(vy - 1) * vx + 0] if back.size() == vx * vy else -1.0,
		"mid": back[MID_ROW * vx + MID_COL] if back.size() == vx * vy else -1.0,
		"blank": back[10 * vx + 10] if back.size() == vx * vy else -1.0,
	}
	result["written"] = {"sw": SW_ALPHA, "nw": NW_ALPHA, "mid": MID_ALPHA}
	result["mid_row"] = MID_ROW
	result["mid_col"] = MID_COL

	# A PNG whose dimensions do not match the vertex grid must be refused, not silently mis-mapped
	# into the alpha array (it would smear every layer by one row from then on).
	var mismatched := Image.create(vx + 1, vy, false, Image.FORMAT_L8)
	var mismatch_path := png_path.get_basename() + "_mismatch.png"
	mismatched.save_png(mismatch_path)
	result["mismatch_returns_empty"] = SplatmapIo.load_alpha(mismatch_path, terrain).is_empty()


func _probe_empty_layers(result: Dictionary, terrain: TerrainGrid) -> void:
	# What a "delete the last layer" button would leave behind. clampi(i, 0, -1) used to yield -1,
	# and GDScript's negative indexing then made layers[active] throw on the next refresh.
	var orphan := SplatTool.new()
	root.add_child(orphan)
	orphan.configure(terrain, null)
	orphan.layers.clear()
	orphan.set_active(2)
	result["empty_layers"] = {"active": orphan.active, "texture": orphan.active_texture()}


func _probe_ui_sync(result: Dictionary, splat: SplatTool) -> void:
	var opt := OptionButton.new()
	var tex_edit := LineEdit.new()
	root.add_child(opt)
	root.add_child(tex_edit)

	SplatUi.sync_layer_controls(opt, tex_edit, splat)
	var initial_items := opt.item_count
	opt.set_item_metadata(0, "sentinel")

	# A held brush stroke: `changed` fires every tick. The dropdown must survive it intact — a
	# rebuild here closes an open popup and drops the metadata.
	for _i in SYNC_TICKS:
		SplatUi.sync_layer_controls(opt, tex_edit, splat)
	var idle_sync := {
		"items": opt.item_count,
		"selected": opt.selected,
		"metadata_kept": opt.get_item_metadata(0) == "sentinel",
		"text": tex_edit.text,
	}

	# A real layer-set change still has to rebuild the dropdown.
	splat.add_layer(ADDED_LAYER)
	SplatUi.sync_layer_controls(opt, tex_edit, splat)
	var after_add := {
		"items": opt.item_count,
		"selected": opt.selected,
		"metadata_kept": opt.get_item_metadata(0) == "sentinel",
		"text": tex_edit.text,
	}

	# Typing an LTEX ref into the focused field while painting must not be wiped mid-keystroke.
	tex_edit.grab_focus()
	var focused: bool = tex_edit.has_focus()
	tex_edit.text = HALF_TYPED
	for _i in SYNC_TICKS:
		SplatUi.sync_layer_controls(opt, tex_edit, splat)
	var while_typing := tex_edit.text

	# Once the field is no longer being edited the tool's value comes back.
	tex_edit.release_focus()
	SplatUi.sync_layer_controls(opt, tex_edit, splat)

	result["ui_sync"] = {
		"initial_items": initial_items,
		"idle": idle_sync,
		"after_add": after_add,
		"focus_actually_taken": focused,
		"while_typing": while_typing,
		"after_release": tex_edit.text,
		"added_layer": ADDED_LAYER,
		"half_typed": HALF_TYPED,
	}
