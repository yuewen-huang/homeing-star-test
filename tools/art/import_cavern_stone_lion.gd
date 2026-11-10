extends SceneTree
## Usage: godot --headless --script <this file> -- <source directory> <output directory>
## Crop the approved 256 px cells around a fixed origin, keeping the authored five colors.

const SOURCE_CELL := 256
const CELL := Vector2i(152, 120)
const ORIGIN := Vector2i(76, 96)
const COLUMNS := 4
const CLIPS := [
	["出现", "appear", 4, 23], ["待机", "idle", 4, 16],
	["冲刺", "charge", 6, 32], ["转身", "turn", 4, 16],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected source and output directories")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	for clip in CLIPS:
		if not _export(args[0], args[1], clip):
			quit(1)
			return
	quit()


func _export(source: String, output: String, clip: Array) -> bool:
	var img := Image.load_from_file(source.path_join("石狮子%s.png" % clip[0]))
	var columns: int = clip[2]
	var count: int = clip[3]
	if img == null or img.get_width() != columns * SOURCE_CELL or img.get_height() < ceili(float(count) / columns) * SOURCE_CELL:
		push_error("Unexpected authored atlas dimensions: " + str(clip[0]))
		return false
	img.convert(Image.FORMAT_RGBA8)
	var packed := Image.create_empty(CELL.x * COLUMNS, CELL.y * ceili(float(count) / COLUMNS), false, Image.FORMAT_RGBA8)
	var colors := {}
	var cell_bounds := Rect2i(0, 0, SOURCE_CELL, SOURCE_CELL)
	for index in count:
		var from := Vector2i(index % columns, index / columns) * SOURCE_CELL
		var cel := img.get_region(Rect2i(from, cell_bounds.size))
		var bounds := cel.get_used_rect()
		var pivot := Vector2i(128, 158)
		if clip[1] == "charge":
			# The last six cells contain horizontal root travel. The physics actor
			# supplies that travel. Keep the authored vertical baseline and poses.
			pivot = Vector2i(206 if index < 26 else bounds.get_center().x, 256)
		var crop := Rect2i(pivot - ORIGIN, CELL)
		if not bounds.has_area() or not crop.encloses(bounds):
			push_error("Normalized cell would crop artwork: %s frame %d" % [clip[1], index])
			return false
		var region := crop.intersection(cell_bounds)
		var to := Vector2i(index % COLUMNS, index / COLUMNS) * CELL + region.position - crop.position
		packed.blit_rect(cel, region, to)
		for y in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var color := cel.get_pixel(x, y)
				if color.a > 0.0: colors[color.to_rgba32()] = true
	var path := output.path_join("%s_%dx%d_%df.png" % [clip[1], CELL.x, CELL.y, count])
	if colors.size() != 5:
		push_error("Unexpected authored palette for " + str(clip[1]))
		return false
	var result := _save_indexed(packed, colors.keys(), path)
	print("%s: %d cels, %d colors, %s -> %s" % [clip[1], count, colors.size(), img.get_size(), packed.get_size()])
	return result


func _save_indexed(img: Image, visible: Array, path: String) -> bool:
	# Six palette entries (transparent + the original five) fit in four bits.
	visible.sort()
	visible.push_front(0)
	var rgb := PackedByteArray()
	var alpha := PackedByteArray()
	var lookup := {}
	for i in visible.size():
		var rgba: int = visible[i]
		rgb.append_array(PackedByteArray([(rgba >> 24) & 255, (rgba >> 16) & 255, (rgba >> 8) & 255]))
		alpha.append(rgba & 255)
		lookup[rgba] = i
	var stride := img.get_width() / 2 + 1
	var scanlines := PackedByteArray()
	scanlines.resize(stride * img.get_height())
	for y in img.get_height():
		for x in range(0, img.get_width(), 2):
			var a := img.get_pixel(x, y)
			var b := img.get_pixel(x + 1, y)
			var left: int = 0 if a.a == 0 else lookup[a.to_rgba32()]
			var right: int = 0 if b.a == 0 else lookup[b.to_rgba32()]
			scanlines[y * stride + 1 + x / 2] = (left << 4) | right
	var header := _be32(img.get_width()) + _be32(img.get_height()) + PackedByteArray([4, 3, 0, 0, 0])
	var png := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	png += _chunk("IHDR", header)
	png += _chunk("PLTE", rgb)
	png += _chunk("tRNS", alpha)
	png += _chunk("IDAT", scanlines.compress(FileAccess.COMPRESSION_DEFLATE))
	png += _chunk("IEND", PackedByteArray())
	var decoded := Image.new()
	if decoded.load_png_from_buffer(png) != OK:
		push_error("Could not verify indexed PNG " + path)
		return false
	decoded.convert(Image.FORMAT_RGBA8)
	if decoded.get_data() != img.get_data():
		push_error("Indexed PNG differs from the cropped cels " + path)
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(png)
	return file.get_error() == OK


func _be32(n: int) -> PackedByteArray:
	return PackedByteArray([(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255])


func _chunk(kind: String, bytes: PackedByteArray) -> PackedByteArray:
	var body := kind.to_ascii_buffer() + bytes
	var crc := 0xffffffff
	for byte in body:
		crc ^= byte
		for bit in 8:
			crc = (crc >> 1) ^ (0xedb88320 if crc & 1 else 0)
	return _be32(bytes.size()) + body + _be32(crc ^ 0xffffffff)
