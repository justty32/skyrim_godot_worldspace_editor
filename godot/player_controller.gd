class_name PlayerController
extends CharacterBody3D
## Human-scale walkable avatar for previewing terrain from a player's eye.
## A box body with a first-person camera. WASD move, Shift sprint, Space jump,
## mouse look, ESC to exit back to the editor.

const BOX_W       := 0.6     # m
const BOX_H       := 1.83    # m (≈ Skyrim player height: 128 units × 0.014286)
const EYE_HEIGHT  := 1.7     # m
const SPEED       := 8.0     # m/s
const SPRINT      := 20.0
const JUMP_VEL    := 6.0
const GRAVITY     := 25.0
const MOUSE_SENS  := 0.0025

var _cam: Camera3D
var _yaw   := 0.0
var _pitch := 0.0
var _active := false

signal exited


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(BOX_W, BOX_H, BOX_W)
	mesh.mesh = bm
	mesh.position.y = BOX_H * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.3, 0.2)
	mesh.material_override = mat
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new(); shape.size = Vector3(BOX_W, BOX_H, BOX_W)
	col.shape = shape
	col.position.y = BOX_H * 0.5
	add_child(col)

	_cam = Camera3D.new()
	_cam.position.y = EYE_HEIGHT
	_cam.near = 0.05
	_cam.far  = 5000.0
	add_child(_cam)


func activate() -> void:
	_active = true
	_cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func deactivate() -> void:
	_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		_yaw   -= event.relative.x * MOUSE_SENS
		_pitch  = clampf(_pitch - event.relative.y * MOUSE_SENS, -1.5, 1.5)
		rotation.y     = _yaw
		_cam.rotation.x = _pitch
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		deactivate()
		exited.emit()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): input_dir.x += 1.0
	input_dir = input_dir.normalized()

	var speed := SPRINT if Input.is_key_pressed(KEY_SHIFT) else SPEED
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VEL

	move_and_slide()
