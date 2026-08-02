class_name Png16Codec

static func write_chunk(file: FileAccess, type_4b: Array, data: PackedByteArray) -> void:
	file.store_buffer(u32(data.size()))
	var tb := PackedByteArray(type_4b)
	file.store_buffer(tb)
	file.store_buffer(data)
	var crc_src := PackedByteArray()
	crc_src.append_array(tb)
	crc_src.append_array(data)
	file.store_buffer(u32(crc32(crc_src)))


static func u32(v: int) -> PackedByteArray:
	return PackedByteArray([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF])


static func crc32(data: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for byte in data:
		crc ^= byte
		for _i in 8:
			crc = (crc >> 1) ^ (0xEDB88320 if (crc & 1) else 0)
	return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF


static func _be32(d: PackedByteArray, o: int) -> int:
	return (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]


static func _paeth(a: int, b: int, c: int) -> int:
	var p := a + b - c
	var pa := absi(p - a); var pb := absi(p - b); var pc := absi(p - c)
	if pa <= pb and pa <= pc: return a
	if pb <= pc: return b
	return c


## Decode a 16-bit grayscale (color type 0, bit depth 16, non-interlaced) PNG into its raw samples,
## row-major in image order (img row 0 = top), size exp_w × exp_h, each 0..65535. Handles all five
## PNG scanline filters so a heightmap edited in an external 16-bit editor re-imports correctly.
## Returns an empty array on any mismatch/parse failure (after push_error).
static func decode_l16(path: String, exp_w: int, exp_h: int) -> PackedInt32Array:
	var empty := PackedInt32Array()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		push_error("Png16.decode: not a PNG: " + path); return empty

	var width := 0; var height := 0; var bit_depth := 0; var color_type := 0; var interlace := 0
	var idat := PackedByteArray()
	var pos := 8
	while pos + 8 <= bytes.size():
		var len := _be32(bytes, pos)
		var type := bytes.slice(pos + 4, pos + 8).get_string_from_ascii()
		var data_at := pos + 8
		if type == "IHDR":
			width      = _be32(bytes, data_at)
			height     = _be32(bytes, data_at + 4)
			bit_depth  = bytes[data_at + 8]
			color_type = bytes[data_at + 9]
			interlace  = bytes[data_at + 12]
		elif type == "IDAT":
			idat.append_array(bytes.slice(data_at, data_at + len))
		elif type == "IEND":
			break
		pos = data_at + len + 4   # skip data + CRC

	if bit_depth != 16 or color_type != 0 or interlace != 0:
		push_error("Png16.decode: need 16-bit grayscale non-interlaced (got depth=%d type=%d interlace=%d): %s"
			% [bit_depth, color_type, interlace, path]); return empty
	if width != exp_w or height != exp_h:
		push_error("Png16.decode: size mismatch (expected %dx%d, got %dx%d): %s"
			% [exp_w, exp_h, width, height, path]); return empty

	var stride := width * 2   # bytes per scanline of pixel data (1 sample × 2 bytes)
	# Godot's COMPRESSION_DEFLATE is a zlib stream (RFC 1950) — what PNG IDAT requires.
	var raw := idat.decompress_dynamic((1 + stride) * height, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != (1 + stride) * height:
		push_error("Png16.decode: bad IDAT size (got %d, want %d): %s"
			% [raw.size(), (1 + stride) * height, path]); return empty

	# Undo per-scanline filters into `out` (height × stride unfiltered bytes); bpp = 2.
	var bpp := 2
	var out := PackedByteArray(); out.resize(stride * height)
	var src := 0
	for row in height:
		var filter := raw[src]; src += 1
		var ro := row * stride
		for i in stride:
			var x := raw[src + i]
			var a := out[ro + i - bpp] if i >= bpp else 0
			var b := out[ro - stride + i] if row > 0 else 0
			var c := out[ro - stride + i - bpp] if (i >= bpp and row > 0) else 0
			var recon := x
			match filter:
				1: recon = x + a
				2: recon = x + b
				3: recon = x + ((a + b) >> 1)
				4: recon = x + _paeth(a, b, c)
			out[ro + i] = recon & 0xFF
		src += stride

	var samples := PackedInt32Array(); samples.resize(width * height)
	for row in height:
		var ro := row * stride
		for col in width:
			samples[row * width + col] = (out[ro + col * 2] << 8) | out[ro + col * 2 + 1]
	return samples
