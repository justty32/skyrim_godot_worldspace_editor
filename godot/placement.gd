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


var texture_fetch: ObjTexFetch


func apply_textures(sidecar: Dictionary) -> void:
	if _model == null or texture_fetch == null or sidecar.get("contract") != "gltf-textures/1":
		return
	var instances: Array[MeshInstance3D] = []
	_collect_meshes(_model, instances)
	var entries: Array = sidecar.get("meshes", [])
	for i in range(instances.size()):
		var instance := instances[i]
		var matched: Dictionary = {}
		for entry in entries:
			if entry.get("name", "") == str(instance.name):
				matched = entry
				break
		if matched.is_empty():
			for entry in entries:
				if entry.get("index", -1) == i:
					matched = entry
					break
		var tex := texture_fetch.get_texture(matched.get("diffuse", ""))
		if tex == null or instance.mesh == null:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_texture = tex
		instance.material_override = material
		for surface in range(instance.mesh.get_surface_count()):
			instance.set_surface_override_material(surface, material)


static func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_meshes(child, result)
