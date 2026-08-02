class_name PlacementTool
extends Node3D
## Manages object placement: spawn box proxies on the terrain surface, track
## them, and feed PlacementsIo. Active only while main.gd is in Place mode.
##
## Placement pen state (current_*) is driven by the placement UI; each click
## stamps an object with the current base / instance / rotation / scale.

var terrain: TerrainGrid
var _models: ModelFetch   # resolves base ref → real mesh (may be null/offline)

var current_base: String        = "Skyrim.esm:0x018199"   # RockL01 (a visible STAT) by default
var current_instance_id: String = ""
var current_scale: float        = 1.0
var current_rot_x: float        = 0.0  # radians, Godot X (pitch / tilt)
var current_rot_y: float        = 0.0  # radians, Godot Y (yaw)
var current_rot_z: float        = 0.0  # radians, Godot Z (roll / tilt)

var _objects: Array[PlacedObject] = []

signal changed  # count changed → UI label refresh


func configure(t: TerrainGrid, models: ModelFetch = null) -> void:
	terrain = t
	_models = models


# Pull every placed object's real vanilla mesh (nif→glTF via ModelFetch) and swap its box proxy.
# allow_fetch=true runs the slow CLI+convert for uncached bases; the WYSIWYG "Load real models" hook.
func refresh_models(allow_fetch: bool = false) -> void:
	if _models == null:
		return
	for obj in _objects:
		if obj.has_model():
			continue
		var m := _models.get_model(obj.skyrim_base, allow_fetch)
		if m != null:
			obj.set_model(m)


# Click placement: keep clicked X/Z, snap Y onto the terrain surface.
func place_at(display_hit: Vector3) -> void:
	var pos := display_hit
	pos.y = terrain.surface_display_y(display_hit)
	_spawn(current_base, current_instance_id, pos,
		Vector3(current_rot_x, current_rot_y, current_rot_z), current_scale)
	changed.emit()


# Import path: restore an object at an exact display transform (no Y snapping).
func restore(base: String, inst_id: String, display_pos: Vector3,
		rot: Vector3, scale_v: float) -> void:
	_spawn(base, inst_id, display_pos, rot, scale_v)
	changed.emit()


func _spawn(base: String, inst_id: String, pos: Vector3, rot: Vector3, scale_v: float) -> void:
	var obj := PlacedObject.new()
	obj.setup(base, inst_id, _color_for(base))
	add_child(obj)
	obj.global_position = pos
	obj.rotation = rot
	obj.uniform_scale = scale_v
	obj.scale = Vector3.ONE * scale_v
	_objects.append(obj)
	# Show the real mesh if it's already cached (cheap); first fetch of a base is the explicit
	# "Load real models" action, so placing stays snappy.
	if _models != null:
		var m := _models.get_model(base, false)
		if m != null:
			obj.set_model(m)


func remove_last() -> void:
	if _objects.is_empty():
		return
	_objects.pop_back().queue_free()
	changed.emit()


func clear_all() -> void:
	for obj in _objects:
		obj.queue_free()
	_objects.clear()
	changed.emit()


func count() -> int:
	return _objects.size()


func objects() -> Array[PlacedObject]:
	return _objects


# Deterministic colour from the base ref so distinct bases read differently.
static func _color_for(base: String) -> Color:
	return Color.from_hsv(float(absi(hash(base)) % 360) / 360.0, 0.6, 0.9)
