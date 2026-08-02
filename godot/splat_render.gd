class_name SplatRender
## Bridges the SplatTool's layer data to the terrain's visual: either the WYSIWYG real-texture
## blend (TerrainMaterial via the resolved LTEX textures) or the height-gradient tint fallback.
## Split out of splat_tool.gd so the tool itself stays "layer model + paint pen". Static helpers
## operate on the passed `tool` (its layers / active / base_texture / _tex_fetch / _terrain).

# Display tints cycled per layer index — only used by the no-real-textures fallback overlay.
const LAYER_TINTS := [
	Color(0.30, 0.62, 0.25),  # grass green
	Color(0.62, 0.34, 0.20),  # dirt brown
	Color(0.70, 0.70, 0.74),  # rock grey
	Color(0.92, 0.92, 0.96),  # snow white
]


static func has_real_textures(tool: SplatTool) -> bool:
	return tool._tex_fetch != null and tool._tex_fetch.available()


# Resolve every layer (+ base) to a real Texture2D and push the WYSIWYG blend into the terrain.
# allow_fetch=true permits the slow CLI+convert for refs not yet cached; false only loads disk cache.
static func refresh_textures(tool: SplatTool, allow_fetch: bool) -> void:
	if tool._terrain == null:
		return
	var base_tex: Texture2D = tool._tex_fetch.get_texture(tool.base_texture, allow_fetch) if tool._tex_fetch else null
	var resolved: Array = []
	for l in tool.layers:
		var t: Texture2D = tool._tex_fetch.get_texture(l["texture"], allow_fetch) if tool._tex_fetch else null
		resolved.append({ "tex": t, "alpha": l["alpha"] })
	tool._terrain.apply_textures(base_tex, resolved)


# Update the terrain after an alpha/active/base change: real-texture blend (cheap, cached) if
# available, else the height-gradient tint (needs a mesh rebuild).
static func refresh_visual(tool: SplatTool) -> void:
	if has_real_textures(tool):
		refresh_textures(tool, false)
	else:
		push_overlay(tool)
		tool._terrain.rebuild_mesh()


# Share the active layer's alpha + tint into the terrain for the vertex-colour fallback path.
static func push_overlay(tool: SplatTool) -> void:
	tool._terrain.splat_overlay_alpha = tool.layers[tool.active]["alpha"]
	tool._terrain.splat_overlay_color = LAYER_TINTS[tool.active % LAYER_TINTS.size()]
