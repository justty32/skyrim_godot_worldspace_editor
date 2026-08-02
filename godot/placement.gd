class_name PlacedObject
extends Node3D
## One placed worldspace object: a thin metadata carrier + a visual proxy.
##
## The visual is a colour-coded box by default; once ModelFetch resolves the base ref's real
## vanilla mesh (nif→glTF), set_model swaps in the actual model (WYSIWYG). Only position /
## rotation / uniform_scale feed placements.json — the visual is never exported.

var skyrim_base: String = ""    # "<master>:0xFORMID" or in-spec editorId
var instance_id: String = ""    # "" = anonymous REFR (omitted from export)
var uniform_scale: float = 1.0  # Skyrim REFR scale, independent of display scales

const _BOX_SIZE := Vector3(1.5, 3.0, 1.5)  # rough humanoid-ish proxy, metres
# glTF models from nif2gltf are in Skyrim game units; the terrain shows units at this metre scale.
const _GAME_UNITS_TO_M := TerrainGrid.METERS_PER_UNIT

var _box: MeshInstance3D = null
var _model: Node3D = null


func setup(base: String, inst_id: String, color: Color) -> void:
	skyrim_base = base
	instance_id = inst_id
	_box = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _BOX_SIZE
	_box.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	_box.material_override = mat
	_box.position = Vector3(0, _BOX_SIZE.y * 0.5, 0)  # base sits at the node origin (feet)
	add_child(_box)


# Swap the box proxy for the real model (game-unit mesh scaled to display metres). The node's own
# uniform_scale (REFR scale) still multiplies on top. Replaces any previously-set model.
func set_model(model: Node3D) -> void:
	if _model != null:
		_model.queue_free()
	_model = model
	model.scale = Vector3.ONE * _GAME_UNITS_TO_M
	add_child(model)
	if _box != null:
		_box.visible = false


func has_model() -> bool:
	return _model != null
