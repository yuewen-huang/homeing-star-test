extends SceneTree
## Run against combat-vfx-studio. Bakes the same brush rings as the editable combo.

const SOURCE := "res://combos/clockwork_bird_ring_slashes/"
const CELL := Vector2i(256, 88)
const COLUMNS := 8
const FPS := 120
const WORKSPACE := "E:/HomingStar"
const OUTPUT := WORKSPACE + "/homeing-star-game/assets/enemies/clockwork_bird/"


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	ComboStyle.load_file(SOURCE + "style.json")
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "combo.json"))
	var slashes := (document.events as Array).filter(func(e: Dictionary) -> bool: return e.do == "slash")
	var hits := (document.events as Array).filter(func(e: Dictionary) -> bool: return e.do == "hit")
	assert(slashes.size() == 10 and hits.size() == slashes.size())
	var normal: Dictionary = slashes.front()
	var red: Dictionary = slashes.back()
	var normal_frames := _frames(normal)
	var red_frames := _frames(red)
	var rows := ceili(float(normal_frames + red_frames) / COLUMNS)
	var atlas := Image.create_empty(CELL.x * COLUMNS, CELL.y * rows, false, Image.FORMAT_RGBA8)
	var view := SubViewport.new()
	view.size = CELL
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)

	await _draw_strip(view, atlas, normal, 0, normal_frames)
	await _draw_strip(view, atlas, red, normal_frames, red_frames)
	var timeline: Array[Dictionary] = []
	for index in slashes.size():
		var cut: Dictionary = slashes[index]
		timeline.append({
			"release": cut.t, "hit": hits[index].t, "y": cut.y_offset,
			"mirrored": float(cut.from) > float(cut.to), "red": cut.palette == "red",
		})
	var properties := {
		"cuts": timeline, "fps": FPS, "cell": [CELL.x, CELL.y], "columns": COLUMNS,
		"normal_frames": normal_frames, "red_frames": red_frames,
		"normal_extent": [normal.radius, float(normal.radius) * float(normal.squash)],
		"red_extent": [red.radius, float(red.radius) * float(red.squash)],
	}
	var error := atlas.save_png(OUTPUT + "spin_ring.png")
	assert(error == OK)
	var metadata := FileAccess.open(OUTPUT + "spin_ring.json", FileAccess.WRITE)
	metadata.store_string(JSON.stringify(properties, "\t") + "\n")
	metadata.close()
	view.queue_free()
	print("CLOCKWORK RING BAKE: ", normal_frames, " normal frames, ", red_frames, " red frames, ",
		timeline.size(), " cuts")
	quit()


func _frames(event: Dictionary) -> int:
	return ceili((float(event.duration) + float(event.hold) + float(event.fade)) * FPS)


func _draw_strip(view: SubViewport, atlas: Image, event: Dictionary, start: int, count: int) -> void:
	var ring := PixelSlash.new().configure({
		"shape": &"crescent", "radius": float(event.radius), "squash": float(event.squash),
		"width": float(event.width), "start_angle": deg_to_rad(float(event.from)),
		"end_angle": deg_to_rad(float(event.to)), "duration": float(event.duration),
		"hold": float(event.hold), "fade": float(event.fade), "palette": StringName(event.palette),
	})
	ring.position = Vector2(CELL) * 0.5
	view.add_child(ring)
	for index in count:
		ring.advance((0.5 if index == 0 else 1.0) / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels := view.get_texture().get_image()
		var slot := start + index
		var at := Vector2i(slot % COLUMNS, slot / COLUMNS) * CELL
		atlas.blit_rect(pixels, Rect2i(Vector2i.ZERO, CELL), at)
	ring.free()
