extends SceneTree

## Offline art packaging only. Does not instantiate gameplay or change scenes.
const KIT := "res://assets/sideview/environment/chapter_1_vine/terrain/ground_v1/"
const PREVIEW := "res://docs/art_prompts/chapter_1_vine/"
const WIDTHS := {"long": 420, "short": 220, "edge_left": 310, "edge_right": 260,
	"slope_up": 220, "slope_down": 220, "crumble": 220, "permanent": 420}
var profiles := {}
var manifest := {}

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	for key in WIDTHS:
		var source := Image.load_from_file(KIT + "candidates/" + key + "_source.png")
		if source == null:
			push_error("Missing art source: " + key)
			quit(1)
			return
		source.convert(Image.FORMAT_RGBA8)
		var bounds := alpha_bounds(source)
		var cut := source.get_region(bounds)
		var width: int = WIDTHS[key]
		var factor := float(width - 12) / bounds.size.x
		var height := roundi(bounds.size.y * factor)
		cut.resize(width - 12, height, Image.INTERPOLATE_LANCZOS)
		var output := Image.create(width, height + 12, false, Image.FORMAT_RGBA8)
		output.blit_rect(cut, Rect2i(Vector2i.ZERO, cut.get_size()), Vector2i(6, 6))
		var filename: String = "vine_ground_" + key + ".png"
		output.save_png(KIT + filename)
		var profile := measure(output, key.begins_with("slope_"))
		profiles[filename] = profile
		manifest[filename] = {"source": "candidates/" + key + "_source.png", "size": [width, height + 12],
			"source_size": [source.get_width(), source.get_height()], "crop": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
			"uniform_scale": factor, "alpha_corners": output.get_pixel(0, 0).a}
	var wall := Image.load_from_file(KIT + "candidates/wall_source.png")
	wall.convert(Image.FORMAT_RGBA8)
	wall.resize(147, roundi(wall.get_height() * 147.0 / wall.get_width()), Image.INTERPOLATE_LANCZOS)
	var overlap := 66
	var period := wall.get_height() - overlap
	var tile := wall.get_region(Rect2i(0, 0, 147, period))
	for y in range(overlap):
		var weight := 0.5 - 0.5 * cos(PI * y / (overlap - 1))
		for x in range(147):
			tile.set_pixel(x, y, wall.get_pixel(x, y + period).lerp(wall.get_pixel(x, y), weight))
	tile.save_png(KIT + "vine_ground_wall.png")
	manifest["vine_ground_wall.png"] = {"size": [147, period], "vertical_overlap": overlap, "opaque": true}
	var vine := Image.load_from_file(KIT + "candidates/hanging_vine_source.png")
	vine.convert(Image.FORMAT_RGBA8)
	var vine_cut := vine.get_region(alpha_bounds(vine))
	vine_cut.resize(roundi(vine_cut.get_width() * 480.0 / vine_cut.get_height()), 480, Image.INTERPOLATE_LANCZOS)
	var vine_canvas := Image.create(vine_cut.get_width() + 12, 492, false, Image.FORMAT_RGBA8)
	vine_canvas.blit_rect(vine_cut, Rect2i(Vector2i.ZERO, vine_cut.get_size()), Vector2i(6, 6))
	vine_canvas.save_png(KIT + "vine_hanging_vine.png")
	manifest["vine_hanging_vine.png"] = {"size": [vine_canvas.get_width(), 492], "note": "Artwork only; swinging/deformation is not implemented by this asset."}
	save_json(KIT + "surfaces.json", profiles)
	save_json(KIT + "manifest.json", manifest)
	if DisplayServer.get_name() == "headless":
		print("VINE_ART_PACK_BUILT")
		quit()
	else:
		await render_preview()
		quit()

func alpha_bounds(image: Image) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i.ZERO
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 24.0 / 255.0:
				low.x = mini(low.x, x)
				low.y = mini(low.y, y)
				high.x = maxi(high.x, x)
				high.y = maxi(high.y, y)
	return Rect2i(low, high - low + Vector2i.ONE)

func measure(image: Image, sloped: bool) -> Dictionary:
	# Central top-contour samples avoid the large decorative leaf tufts at ends.
	var points: Array[Vector2] = []
	for x in range(roundi(image.get_width() * 0.22), roundi(image.get_width() * 0.78)):
		for y in range(image.get_height()):
			if image.get_pixel(x, y).a > 0.6:
				points.append(Vector2(x, y))
				break
	var ys: Array[float] = []
	var center := Vector2.ZERO
	for p in points:
		center += p
		ys.append(p.y)
	center /= points.size()
	ys.sort()
	var slope := 0.0
	if sloped:
		var xx := 0.0
		var xy := 0.0
		for p in points:
			xx += pow(p.x - center.x, 2)
			xy += (p.x - center.x) * (p.y - center.y)
		slope = xy / maxf(xx, 0.001)
	else:
		center.y = ys[ys.size() / 2]
	var left := center.y + (6 - center.x) * slope
	var right := center.y + (image.get_width() - 6 - center.x) * slope
	return {"size": [image.get_width(), image.get_height()], "solid_x": [6.0, image.get_width() - 6.0],
		"top_left": snappedf(left, 0.1), "top_right": snappedf(right, 0.1), "median_top": snappedf((left + right) * 0.5, 0.1),
		"fit_slope": snappedf(slope, 0.001)}

func save_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  ", true) + "\n")

func render_preview() -> void:
	root.size = Vector2i(1600, 1050)
	root.content_scale_size = Vector2i(1600, 1050)
	var sheet := ArtSheet.new()
	sheet.profiles = profiles
	root.add_child(sheet)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(PREVIEW + "vine_ground_v1_preview.png")
	sheet.tiling = true
	sheet.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(PREVIEW + "vine_ground_v1_tiling.png")
	print("VINE_ART_PREVIEWS_SAVED")

class ArtSheet extends Node2D:
	var profiles: Dictionary
	var tiling := false
	var textures := {}
	func label(at: Vector2, text: String, size: int = 22) -> void:
		draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color("e9f0e6"))
	func texture(key: String) -> Texture2D:
		if not textures.has(key):
			textures[key] = ImageTexture.create_from_image(Image.load_from_file(KIT + key + ".png"))
		return textures[key]
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1600, 1050), Color("23323a"))
		for y in range(0, 1050, 24):
			for x in range(0, 1600, 24):
				if (x / 24 + y / 24) % 2 == 0:
					draw_rect(Rect2(x, y, 24, 24), Color("283a40"))
		if tiling:
			label(Vector2(35, 45), "藤区地块 v1 · 拼接检查：青线为候选落脚线", 28)
			var start := 40.0
			for key in ["edge_left", "long", "short", "edge_right"]:
				var tex := texture("vine_ground_" + key)
				var info: Dictionary = profiles["vine_ground_" + key + ".png"]
				var at := Vector2(start - 6 * 1.3, 240 - float(info.median_top) * 1.3)
				draw_texture_rect(tex, Rect2(at, tex.get_size() * 1.3), false)
				start += (tex.get_width() - 12) * 1.3 - 34
			draw_line(Vector2(40, 240), Vector2(start + 34, 240), Color.CYAN, 2)
			label(Vector2(35, 385), "墙面纵向连续三段 / 永久落脚台 / 悬挂藤蔓")
			var wall := texture("vine_ground_wall")
			for i in range(3):
				draw_texture_rect(wall, Rect2(Vector2(40, 425 + wall.get_height() * 1.3 * i), wall.get_size() * 1.3), false)
			draw_texture_rect(texture("vine_ground_permanent"), Rect2(350, 465, 546, texture("vine_ground_permanent").get_height() * 1.3), false)
			draw_texture(texture("vine_hanging_vine"), Vector2(1120, 420))
			return
		label(Vector2(35, 45), "藤区地块资源包 v1 · 风区定稿规格 · 美术预览", 28)
		var keys := ["long", "short", "edge_left", "edge_right", "slope_up", "slope_down", "crumble", "permanent"]
		var names := ["长平台", "短平台", "左端头", "右端头", "上坡", "下坡", "易碎块", "永久落脚台"]
		for i in range(keys.size()):
			var key: String = keys[i]
			var at := Vector2(35 + (i % 2) * 680, 105 + (i / 2) * 220)
			label(at, names[i] + " / " + key)
			at.y += 15
			var tex := texture("vine_ground_" + key)
			draw_texture_rect(tex, Rect2(at, tex.get_size() * 1.3), false)
			var p: Dictionary = profiles["vine_ground_" + key + ".png"]
			draw_line(at + Vector2(6, p.top_left) * 1.3, at + Vector2(p.solid_x[1], p.top_right) * 1.3, Color.CYAN, 2)
		label(Vector2(1410, 105), "悬挂藤蔓", 20)
		draw_texture(texture("vine_hanging_vine"), Vector2(1440, 125))
		label(Vector2(1380, 690), "墙面中段", 20)
		draw_texture_rect(texture("vine_ground_wall"), Rect2(1380, 710, 191, texture("vine_ground_wall").get_height() * 1.3), false)
		label(Vector2(35, 1020), "实体不透明；外围真实 alpha。普通地块的延迟坍塌及藤蔓交互由下一阶段接入。", 20)
