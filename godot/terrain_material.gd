class_name TerrainMaterial
## Builds/updates the terrain's ShaderMaterial for WYSIWYG texturing: a tiled base ground texture
## with up to 4 splat layers blended by their per-vertex alpha grids (the SAME grids exported to
## the splatmap PNGs, so the editor preview matches what ModForge bakes into VTXT). When no real
## textures are loaded (offline / not fetched) the shader falls back to the height-gradient vertex
## colour, so behaviour is unchanged until the user pulls textures in.
##
## Alpha grids and UV share row-0=south / col-0=west indexing, so a layer painted in the south-west
## previews in the south-west — the in-game blend direction the export's VTXT position order encodes.

const MAX_LAYERS := 4

const SHADER_SRC := "
shader_type spatial;
render_mode cull_back, diffuse_burley;

uniform bool textured = false;
uniform float uv_scale = 24.0;
uniform int layer_count = 0;
uniform sampler2D base_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D ltex0 : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D ltex1 : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D ltex2 : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D ltex3 : source_color, hint_default_white, filter_linear_mipmap;
uniform sampler2D alpha0 : hint_default_black, filter_linear;
uniform sampler2D alpha1 : hint_default_black, filter_linear;
uniform sampler2D alpha2 : hint_default_black, filter_linear;
uniform sampler2D alpha3 : hint_default_black, filter_linear;

void fragment() {
	if (!textured) {
		ALBEDO = COLOR.rgb;
	} else {
		vec2 tuv = UV * uv_scale;
		vec3 col = texture(base_tex, tuv).rgb;
		if (layer_count > 0) col = mix(col, texture(ltex0, tuv).rgb, texture(alpha0, UV).r);
		if (layer_count > 1) col = mix(col, texture(ltex1, tuv).rgb, texture(alpha1, UV).r);
		if (layer_count > 2) col = mix(col, texture(ltex2, tuv).rgb, texture(alpha2, UV).r);
		if (layer_count > 3) col = mix(col, texture(ltex3, tuv).rgb, texture(alpha3, UV).r);
		ALBEDO = col;
	}
	ROUGHNESS = 0.9;
}
"


static func make() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADER_SRC
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# Build an R-float alpha texture from a per-vertex alpha grid (row0=south, col0=west).
static func alpha_texture(alpha: PackedFloat32Array, vx: int, vy: int) -> ImageTexture:
	if alpha.size() != vx * vy:
		return null
	var img := Image.create_from_data(vx, vy, false, Image.FORMAT_RF, alpha.to_byte_array())
	return ImageTexture.create_from_image(img)


# Push base + layers into the material. `base_tex` may be null (white). `layers` is an Array of
# { "tex": Texture2D|null, "alpha": PackedFloat32Array }. Sets textured=true only if a base or any
# layer texture actually resolved — otherwise the shader keeps the height-gradient fallback.
static func apply(m: ShaderMaterial, base_tex: Texture2D, layers: Array, vx: int, vy: int, uv_scale: float) -> void:
	var any := base_tex != null
	m.set_shader_parameter("base_tex", base_tex)
	m.set_shader_parameter("uv_scale", uv_scale)
	var n := mini(layers.size(), MAX_LAYERS)
	m.set_shader_parameter("layer_count", n)
	for i in MAX_LAYERS:
		var tex: Texture2D = null
		var atex: ImageTexture = null
		if i < n:
			tex = layers[i].get("tex")
			atex = alpha_texture(layers[i].get("alpha", PackedFloat32Array()), vx, vy)
			if tex != null:
				any = true
		m.set_shader_parameter("ltex%d" % i, tex)
		m.set_shader_parameter("alpha%d" % i, atex)
	m.set_shader_parameter("textured", any)
