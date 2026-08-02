class_name UiSection
## A collapsible side-panel section: a full-width toggle header button (▼ open / ▶ closed) plus a
## content VBox beneath it that the header shows/hides. Returns the content VBox so each big group
## (Height / Object / Texture) fills it with their own sliders/buttons. Lets the user fold away a
## whole group to declutter the panel. Used by world_ui / placement_ui / splat_ui.

static func make(parent: VBoxContainer, title: String, expanded: bool = true) -> VBoxContainer:
	parent.add_child(HSeparator.new())

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	content.visible = expanded

	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = expanded
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 14)
	header.text = ("▼ " if expanded else "▶ ") + title
	header.toggled.connect(func(on: bool):
		content.visible = on
		header.text = ("▼ " if on else "▶ ") + title)

	parent.add_child(header)
	parent.add_child(content)
	return content
