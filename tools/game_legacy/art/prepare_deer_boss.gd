extends SceneTree

const SOURCE := "res://../homing-star-test/PendingArt/character/朽角巡林者/"
const OUTPUT := "res://assets/sideview/characters/xiujiao_ranger/boss/"
const ACTIONS := {
	"idle": ["待机", "2", 32], "walk": ["步行", "3", 16],
	"charge": ["冲刺上挑", "4", 32], "light": ["轻击", "5", 16],
	"heavy": ["重击", "6", 32], "roar": ["鹿鸣", "7", 16],
	"hurt": ["受击", "8", 16], "death": ["死亡", "9", 12],
}

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var core_positions := {}
	for action: String in ACTIONS:
		var spec: Array = ACTIONS[action]
		var path := ProjectSettings.globalize_path(SOURCE + "%s/image-2-godot4 (%s)/image-2/textures/image-2_spritesheet.png" % [spec[0], spec[1]])
		var source := Image.load_from_file(path)
		assert(source != null, path)
		var count: int = spec[2]
		var strip := Image.create(256 * count, 256, false, Image.FORMAT_RGBA8)
		var columns := source.get_width() / 256
		var cores: Array = []
		for index in count:
			var frame := source.get_region(Rect2i((index % columns) * 256, (index / columns) * 256, 256, 256))
			var bounds := frame.get_used_rect()
			# Keep the source proportions and align the lowest opaque foot pixel.
			strip.blit_rect(frame, bounds, Vector2i(index * 256 + bounds.position.x, 252 - bounds.size.y))
			var core := _core_center(frame)
			core.y += 252 - bounds.end.y
			cores.append([core.x, core.y])
		core_positions[action] = cores
		assert(strip.save_png(OUTPUT + "%s_256x256_%df.png" % [action, count]) == OK)
		if action == "idle":
			var portrait := strip.get_region(Rect2i(92, 16, 130, 130))
			portrait.resize(106, 106, Image.INTERPOLATE_NEAREST)
			assert(portrait.save_png(OUTPUT + "portrait.png") == OK)
	_generate_vine_icon()
	var metadata := Resource.new()
	metadata.set_meta(&"core_positions", core_positions)
	assert(ResourceSaver.save(metadata, OUTPUT + "core_positions.tres") == OK)
	print("DEER ART: 8 aligned action strips; death ends at frame 11; generated vine icon")
	quit()

func _core_center(frame: Image) -> Vector2:
	var total := 0.0
	var position := Vector2.ZERO
	for y in range(60, 250):
		for x in range(60, 235):
			var c := frame.get_pixel(x, y)
			var weight := maxf(c.g - maxf(c.r, c.b) - 0.09, 0.0) * pow(c.g, 8) * c.a
			total += weight
			position += Vector2(x, y) * weight
	return position / total if total > 0.001 else Vector2(165, 170)

func _generate_vine_icon() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var p := Vector2(x - 15.5, y - 15.5)
			var radius := p.length()
			var ring := absf(radius - 9.0) < 1.6 and (p.y < 7 or p.x > 0)
			var stem := absf(p.x - sin(p.y * 0.3) * 4) < 1.4 and p.y > 2
			var leaf := absf(p.x + p.y * 0.8 + 8) + absf(p.y + 5) * 0.5 < 4
			if ring or stem or leaf:
				image.set_pixel(x, y, Color("a4e27a") if (x + y) % 3 == 0 else Color("53884b"))
	var outlined := image.duplicate() as Image
	for y in 32:
		for x in 32:
			if image.get_pixel(x, y).a > 0:
				continue
			for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var p: Vector2i = Vector2i(x, y) + n
				if Rect2i(0, 0, 32, 32).has_point(p) and image.get_pixelv(p).a > 0:
					outlined.set_pixel(x, y, Color("1d3024"))
	assert(outlined.save_png(OUTPUT + "vine_snare_icon.png") == OK)
