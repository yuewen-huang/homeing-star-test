extends SceneTree
## yin_air_write (350x350 canvas) vs yin_idle (256x256 canvas) in the BOSS development room.
## Writes: room shots, an idle | air_write | onion side-by-side, an idle -> air_write -> idle
## sequence strip, per-frame crops of eight frames (largest ink arcs included) and an annotated
## contact sheet. Green line = foot line, magenta box = the 350x350 cell bounds.
## Usage: godot --path <game> --script <this> -- <output_dir>   (needs a real window, not --headless)

const PANEL := Vector2i(400, 400)
const PANEL_ORIGIN := Vector2i(200, 330)  ## foot position inside a panel
const ARC_FRAMES := [5, 7, 10, 17, 19, 20, 22, 23]

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
		var anchor := PandaActions.foot_anchor(PandaActions.spec(&"yin_air_write"))
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
	var aw := PandaActions.spec(&"yin_air_write")
	var cell := PandaActions.frame_size(aw)
	var idle_fps := float(PandaActions.spec(&"yin_idle").fps)
	# 1. idle | air_write | onion, frame 0 of each
	pose(&"yin_idle", 0)
	var idle_room := await grab()
	idle_room.save_png(out_dir.path_join("00_room_yin_idle_f00.png"))
	var idle_panel := panel_of(idle_room)
	pose(&"yin_air_write", 0)
	var aw0_room := await grab()
	var aw0_panel := panel_of(aw0_room)
	var onion := idle_panel.duplicate() as Image
	for y in PANEL.y:
		for x in PANEL.x:
			var a := idle_panel.get_pixel(x, y)
			var b := aw0_panel.get_pixel(x, y)
			if a != b: onion.set_pixel(x, y, Color(1, 0.2, 0.2).lerp(b, 0.35) if a.a > b.a else Color(0.2, 0.5, 1.0).lerp(a, 0.35))
	sheet([annotate(idle_panel), annotate(aw0_panel, cell), annotate(onion)], 3).save_png(out_dir.path_join("01_yin_idle_vs_air_write_f00_foot_aligned.png"))
	print("idle f0 vs air_write f0 differing panel pixels: %d of %d" % [differing(idle_panel, aw0_panel), PANEL.x * PANEL.y])
	# 2. sequence idle -> air_write frames -> automatic return to idle
	var strip: Array = [annotate(idle_panel)]
	for f in [0, 4, 8, 16, 24, 31]:
		pose(&"yin_air_write", f)
		strip.append(annotate(panel_of(await grab()), cell))
	pose(&"yin_air_write", 0)
	boss.request_end()  # ING loops until END is requested
	while boss.action == &"yin_air_write":
		boss.tick(1.0 / float(aw.fps))
	print("after play the action is %s at frame %d" % [boss.action, boss.animated_sprite.frame])
	boss.tick(0.5 / idle_fps)
	var after_panel := panel_of(await grab())
	strip.append(annotate(after_panel))
	sheet(strip, 4).save_png(out_dir.path_join("02_sequence_idle_air_write_idle.png"))
	print("yin_idle before vs after air_write, differing panel pixels: %d" % differing(idle_panel, after_panel))
	# 3. eight frames incl. the largest ink arcs
	var contact: Array = []
	for f in ARC_FRAMES:
		pose(&"yin_air_write", f)
		var room_image := await grab()
		var p := panel_of(room_image)
		p.save_png(out_dir.path_join("03_air_write_f%02d_crop.png" % f))
		contact.append(annotate(p, cell))
		if f == 7: room_image.save_png(out_dir.path_join("00_room_yin_air_write_f07.png"))
	sheet(contact, 4).save_png(out_dir.path_join("04_air_write_arc_frames_contact_sheet.png"))
	# 4. START / ING / END split: room shots with the panel status line, plus the ING seam 25 -> 4.
	for entry in [[2, "START"], [14, "ING"], [28, "END"]]:
		pose(&"yin_air_write", entry[0])
		boss.segment = PandaActions.segment_of(aw, entry[0])
		(await grab()).save_png(out_dir.path_join("05_split_%s_f%02d_room.png" % [entry[1], entry[0]]))
	pose(&"yin_air_write", 25)
	var seam_a := panel_of(await grab())
	pose(&"yin_air_write", 4)
	var seam_b := panel_of(await grab())
	var seam_onion := seam_a.duplicate() as Image
	for y in PANEL.y:
		for x in PANEL.x:
			var a := seam_a.get_pixel(x, y)
			var b := seam_b.get_pixel(x, y)
			if a != b: seam_onion.set_pixel(x, y, Color(1, 0.2, 0.2).lerp(b, 0.35) if a.a > b.a else Color(0.2, 0.5, 1.0).lerp(a, 0.35))
	sheet([annotate(seam_a, cell), annotate(seam_b, cell), annotate(seam_onion)], 3).save_png(out_dir.path_join("06_ing_seam_f25_to_f04.png"))
	print("Captured air_write 350 comparison")
	quit()
