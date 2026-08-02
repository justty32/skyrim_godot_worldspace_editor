class_name ShiftScroll
extends ScrollContainer
## A ScrollContainer that only scrolls vertically when Shift is held during the wheel — plain
## wheel over the panel is swallowed (so it never scrolls accidentally while the user means to
## zoom the camera). camera_rig.gd correspondingly ignores Shift+wheel, so the modifier cleanly
## splits the two actions: wheel = camera zoom, Shift+wheel = panel scroll.

const STEP := 40   # pixels per wheel notch

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var b: int = event.button_index
		if b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN:
			if event.shift_pressed:
				var dir := -1 if b == MOUSE_BUTTON_WHEEL_UP else 1
				scroll_vertical += dir * STEP
			# Swallow the wheel either way: with Shift we already scrolled; without it we
			# deliberately don't scroll (the native ScrollContainer behavior is replaced).
			accept_event()
