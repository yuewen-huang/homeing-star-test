extends SceneTree
## yang_to_yin (repaired 350x350 sheet) in the BOSS development room, vs the old 256x256 sheet.
## Writes: contact sheet of frames 13-20 (the worst cropped frames of the old sheet), old-vs-new rows for
## the same frames, a yang_idle -> yang_to_yin -> yin_idle sequence strip, and one room shot.
## Green line = foot line, magenta box = the 350x350 cell bounds.
## Usage: godot --path <game> --script <this> -- <output_dir>   (needs a real window, not --headless)

const PANEL := Vector2i(400, 400)
const PANEL_ORIGIN := Vector2i(200, 330)  ## foot position inside a panel
const OLD_SHEET := "E:/HomingStar/.local-data/panda_yang_to_yin_backup/yang_to_yin_256x256_32f.png"

var room
var boss: PandaBoss
var out_dir := ""

func _initialize() -> void:
	call_deferred("run")

func grab() -> Image:
	room._process(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func panel_of(image: Image) -> Image:
	var foot := Vector2i(boss.global_position)
	return image.get_region(Rect2i(foot - PANEL_ORIGIN, PANEL))

func line_h(image: Image, y: int, color: Color) -> void:
	image.fill_rect(Rect2i(0, y, image.get_width(), 1), color)

func box(image: Image, rect: Rect2i, color: Color) -> void:
	image.fill_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, 1), color)
	image.fill_rect(Rect2i(rect.position.x, rect.end.y - 1, rect.size.x, 1), color)
	image.fill_rect(Rect2i(rect.position.x, rect.position.y, 1, rect.size.y), color)
	image.fill_rect(Rect2i(rect.end.x - 1, rect.position.y, 1, rect.size.y), color)

func annotate(panel: Image, cell := Vector2i.ZERO) -> Image:
	var image := panel.duplicate() as Image
	line_h(image, PANEL_ORIGIN.y, Color(0.1, 0.9, 0.2))
	if cell != Vector2i.ZERO:
		var anchor := PandaActions.foot_anchor(PandaActions.spec(&"yang_to_yin"))
		box(image, Rect2i(PANEL_ORIGIN - Vector2i(anchor), cell), Color(1, 0, 1))
	return image

func pose(id: StringName, frame: int) -> void:
	boss.play_action(id)
	boss.tick((frame + 0.5) / float(PandaActions.spec(id).fps))
	boss.animated_sprite.frame = frame  # frames past ING would otherwise wrap into the loop
	room.adapter.panel._refresh()

func sheet(panels: Array, columns: int) -> Image:
	var rows := int(ceil(panels.size() / float(columns)))
	var image := Image.create(columns * (PANEL.x + 4), rows * (PANEL.y + 4), false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.05, 0.08))
	for i in panels.size():
		image.blit_rect(panels[i], Rect2i(Vector2i.ZERO, PANEL), Vector2i((i % columns) * (PANEL.x + 4), (i / columns) * (PANEL.y + 4)))
	return image

func differing(a: Image, b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y): count += 1
	return count

func show_old(frame: int) -> Sprite2D:
	var old := Sprite2D.new()
	old.texture = ImageTexture.create_from_image(Image.load_from_file(OLD_SHEET))
	old.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	old.region_enabled = true
	old.region_rect = Rect2((frame % 6) * 256, (frame / 6) * 256, 256, 256)
	old.centered = false
	old.offset = -PandaActions.FOOT_ANCHOR
	old.scale = boss.animated_sprite.scale
	boss.add_child(old)
	boss.animated_sprite.visible = false
	return old

func hide_old(old: Sprite2D) -> void:
	old.queue_free()
	boss.animated_sprite.visible = true

func run() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.player.set_physics_process(false)
	room.boss_picker.item_selected.emit(9)
	await process_frame
	await process_frame
	boss = room.adapter.boss as PandaBoss
	boss.set_process(false)
	room.adapter.panel.set_process(false)
	var spec := PandaActions.spec(&"yang_to_yin")
	var cell := PandaActions.frame_size(spec)
	# 1. frames 13-20, new vs old, same foot-aligned panel crop
	var new_panels: Array = []
	var old_panels: Array = []
	for f in range(13, 21):
		pose(&"yang_to_yin", f)
		var room_image := await grab()
		var p := panel_of(room_image)
		p.save_png(out_dir.path_join("03_yang_to_yin_f%02d_crop.png" % f))
		new_panels.append(annotate(p, cell))
		if f == 16: room_image.save_png(out_dir.path_join("00_room_yang_to_yin_f16.png"))
		var old := show_old(f)
		old_panels.append(annotate(panel_of(await grab()), Vector2i(256, 256)))
		hide_old(old)
	sheet(new_panels, 4).save_png(out_dir.path_join("01_yang_to_yin_f13-20_new_contact_sheet.png"))
	sheet(old_panels + new_panels, 4).save_png(out_dir.path_join("02_old_top_vs_new_bottom_f13-20.png"))
	# 2. continuous sequence yang_idle -> yang_to_yin -> yin_idle, played through the real tick clock
	var strip: Array = []
	pose(&"yang_idle", 0)
	strip.append(annotate(panel_of(await grab())))
	boss.play_action(&"yang_to_yin")
	var shown := [0, 4, 8, 12, 13, 14, 15, 16, 17, 18, 20, 24, 31]
	var step := 0.0
	var fps := float(spec.fps)
	for f in shown:
		boss.tick((f + 0.5) / fps - step)
		step = (f + 0.5) / fps
		strip.append(annotate(panel_of(await grab()), cell))
	boss.tick(1.0 / fps)
	print("after yang_to_yin the action is %s at frame %d" % [boss.action, boss.animated_sprite.frame])
	strip.append(annotate(panel_of(await grab())))
	sheet(strip, 5).save_png(out_dir.path_join("04_sequence_yang_idle_to_yin_idle.png"))
	print("Captured yang_to_yin fix")
	quit()