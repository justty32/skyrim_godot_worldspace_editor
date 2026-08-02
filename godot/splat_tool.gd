class_name SplatTool
extends Node
## Per-vertex terrain texture-alpha painting (the front end for ModForge
## worldspace.textureLayers). Holds N layers, each = an LTEX ref + an alpha grid sized to the
## terrain vertex grid (verts_x × verts_y). LMB in Splat Mode paints the ACTIVE layer's alpha;
## export writes each layer to an 8-bit grayscale PNG that feeds textureLayers[].splatmap.
##
## Alpha grid is [row * verts_x + col], row 0 = south, col 0 = west — the SAME layout the
## heightmap uses, so a splatmap PNG co-registers with terrain.png vertex-for-vertex.
## Terrain visual (real-texture WYSIWYG blend or tint fallback) is driven by SplatRender.

var _terrain: TerrainGrid
var _tex_fetch: TexFetch       # resolves LTEX refs → real ground textures (may be null/offline)
var layers: Array = []        # each: { "texture": String, "alpha": PackedFloat32Array }
var active: int = 0

# The un-painted ground (BTXT base layer). WYSIWYG shows this everywhere a layer's alpha is 0.
var base_texture := "Skyrim.esm:0x000C14"   # LDirt01

var radius   := 4.0
var strength := 3.0           # alpha gained per second at full falloff
var erase    := false

signal changed                # layer set / active / paint changed


func configure(terrain: TerrainGrid, tex_fetch: TexFetch = null) -> void:
	_terrain = terrain
	_tex_fetch = tex_fetch
	add_layer("Skyrim.esm:0x013428")            # LFieldGrass01 — a real grass layer to start
	SplatRender.refresh_textures(self, false)   # load disk-cached PNGs only; no blocking fetch at startup


func set_base_texture(ref: String) -> void:
	base_texture = ref
	SplatRender.refresh_textures(self, true)    # explicit ref commit → fetch the real texture
	changed.emit()


# Pull real textures + re-blend (the "Load real textures" hook). allow_fetch=true runs the CLI.
func refresh_textures(allow_fetch: bool = false) -> void:
	SplatRender.refresh_textures(self, allow_fetch)


# Remap every layer's alpha grid after the terrain grid was resized (TerrainGrid.resize_cells).
# Old (old_vx × old_vy) values stay at the same (col,row); new verts default to 0 alpha.
func resize_grid(old_vx: int, old_vy: int) -> void:
	var nx := _terrain.verts_x
	var ny := _terrain.verts_y
	for l in layers:
		var old: PackedFloat32Array = l["alpha"]
		var na := PackedFloat32Array()
		na.resize(nx * ny)
		na.fill(0.0)
		for r in mini(old_vy, ny):
			for c in mini(old_vx, nx):
				na[r * nx + c] = old[r * old_vx + c]
		l["alpha"] = na
	SplatRender.refresh_visual(self)
	changed.emit()


func add_layer(texture: String = "") -> void:
	var a := PackedFloat32Array()
	a.resize(_terrain.verts_x * _terrain.verts_y)
	a.fill(0.0)
	layers.append({ "texture": texture, "alpha": a })
	set_active(layers.size() - 1)


func set_active(i: int) -> void:
	active = clampi(i, 0, layers.size() - 1)
	SplatRender.refresh_visual(self)
	changed.emit()


func count() -> int:
	return layers.size()


func active_texture() -> String:
	return layers[active]["texture"]


func set_active_texture(t: String) -> void:
	layers[active]["texture"] = t
	SplatRender.refresh_textures(self, true)   # re-fetch the new LTEX's real ground texture


func clear_active() -> void:
	layers[active]["alpha"].fill(0.0)
	SplatRender.refresh_visual(self)
	changed.emit()


# Paint the active layer's alpha under the cursor, toward 1.0 (or 0.0 when erasing).
func paint(hit_world: Vector3, delta: float) -> void:
	var cv := _terrain.world_to_vert(hit_world)
	var r  := int(ceilf(radius))
	var target := 0.0 if erase else 1.0
	var alpha: PackedFloat32Array = layers[active]["alpha"]
	var touched := false
	for dr in range(-r, r + 1):
		for dc in range(-r, r + 1):
			var row := cv.y + dr
			var col := cv.x + dc
			if row < 0 or row >= _terrain.verts_y or col < 0 or col >= _terrain.verts_x:
				continue
			var dist := Vector2(float(dc), float(dr)).length()
			if dist > radius:
				continue
			var falloff := 1.0 - smoothstep(0.0, radius, dist)
			var i := row * _terrain.verts_x + col
			var amt := minf(delta * strength * falloff, 1.0)
			alpha[i] = clampf(lerpf(alpha[i], target, amt), 0.0, 1.0)
			touched = true
	if touched:
		layers[active]["alpha"] = alpha
		SplatRender.refresh_visual(self)
		changed.emit()
