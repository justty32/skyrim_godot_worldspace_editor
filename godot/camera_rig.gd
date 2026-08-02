class_name CameraRig
extends Node3D
## Orbit camera: middle-drag to orbit, scroll to zoom, right-drag to pan, WASD to pan on the
## ground plane (relative to the camera's facing).

var target := Vector3.ZERO
var distance := 80.0    # meters
var yaw := 30.0         # degrees, horizontal rotation
var pitch := -40.0      # degrees, negative = looking down

var orbit_speed := 0.25
var zoom_factor := 0.12   # fraction of current distance per scroll tick
var pan_speed := 0.04     # fraction of distance per pixel
var wasd_speed := 0.9     # WASD pan: fraction of current distance per second

var _camera: Camera3D
var _orbiting := false
var _panning  := false
var _last_mouse := Vector2.ZERO

func _ready() -> void:
	_camera = Camera3D.new()
	_camera.near = 0.5
	_camera.far = 10000.0
	add_child(_camera)
	_apply_transform()


func get_camera() -> Camera3D:
	return _camera


func refresh() -> void:
	_apply_transform()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_orbiting = event.pressed
				_last_mouse = event.position
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
				_last_mouse = event.position
			MOUSE_BUTTON_WHEEL_UP:
				if not event.shift_pressed:  # Shift+wheel scrolls the side panel; don't zoom
					distance = maxf(2.0, distance * (1.0 - zoom_factor))
					_apply_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				if not event.shift_pressed:
					distance = minf(2000.0, distance * (1.0 + zoom_factor))
					_apply_transform()

	if event is InputEventMouseMotion:
		if _orbiting:
			yaw   -= event.relative.x * orbit_speed
			pitch  = clampf(pitch - event.relative.y * orbit_speed, -85.0, -5.0)
			_apply_transform()
		if _panning:
			var right := _camera.global_transform.basis.x
			var fwd   := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw))).normalized()
			var delta  = event.relative
			target -= right * delta.x * pan_speed * distance * 0.01
			target += fwd   * delta.y * pan_speed * distance * 0.01
			_apply_transform()


# WASD pans the camera target on the ground plane, relative to where the camera faces. Skipped
# while a text field has focus (so typing a ref doesn't slide the view). W/S = forward/back along
# the camera's horizontal heading, A/D = left/right.
func _process(delta: float) -> void:
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is SpinBox or fo is TextEdit:
		return
	var move := Vector3.ZERO
	var fwd   := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw))).normalized()
	var right := _camera.global_transform.basis.x
	right.y = 0.0; right = right.normalized()
	if Input.is_key_pressed(KEY_W): move += fwd
	if Input.is_key_pressed(KEY_S): move -= fwd
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if move == Vector3.ZERO:
		return
	target += move.normalized() * distance * wasd_speed * delta
	_apply_transform()


func _apply_transform() -> void:
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	var offset := Vector3(
		sin(yr) * cos(-pr),
		sin(-pr),
		cos(yr) * cos(-pr)
	) * distance
	global_position = target + offset
	look_at(target, Vector3.UP)
