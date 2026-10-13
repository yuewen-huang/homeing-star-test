extends SceneTree

# Offline art handoff: simulate the real specimen in the dedicated room, then
# capture body, back/front effects and warnings separately on transparent canvas.
const SIZE := Vector2i(512, 384)
const ANCHOR := Vector2(256, 332)
const WORLD_SCALE := 1.0 / 1.4
const FPS := 20
const STEP := 1.0 / 60.0
var room
var deer: DeerBoss
var viewport: SubViewport
var body: Sprite2D
var output := ""
var failed := false
var clips: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func stage(kind: String) -> String:
	if kind == "vine_cage":
		if not deer.snared: return "退回地下"
		if deer.vfx._snare_growth < DeerMistArt.VINE_RISE_TIME / DeerMistArt.VINE_GROW_TIME: return "出土攀升"
		if deer.vfx._snare_growth < 1: return "顶部合拢"
		return "牢笼保持"
	if kind == "mist_ultimate":
		match deer.state:
			DeerBoss.State.CHANT: return "鹿鸣蓄势"
			DeerBoss.State.HUNT_WARNING: return "第%d次冲撞预警" % deer._hunt_round
			DeerBoss.State.HUNT_CHARGE: return "第%d次冲撞" % deer._hunt_round
			DeerBoss.State.HUNT_FINISH: return "最后重踩"
			_: return "收招"
	if deer.state == DeerBoss.State.CHARGE:
		if deer._segment < 0: return "冲刺蓄力"
		if deer._segment == 0: return "冲刺"
		if deer._time < DeerBoss.UPPERCUT_START: return "上挑起势"
		if deer._time < DeerBoss.UPPERCUT_END: return "上挑爆发"
		return "上挑收招"
	var prefix := "第%d击_" % (deer.combo_step + 1) if deer.combo_step >= 0 else ""
	if deer.state == DeerBoss.State.LIGHT:
		return prefix + ("抬蹄" if deer._segment < 0 else ("轻跺爆发" if deer.attack_hitbox.attack != null else "轻跺消散"))
	if deer.state == DeerBoss.State.HEAVY:
		return prefix + ("人立蓄势" if deer._segment < 0 else ("重踩爆发" if deer.attack_hitbox.attack != null else "重踩消散"))
	return "收招"

func advance() -> void:
	deer._physics_process(STEP)
	deer.vfx._process(STEP)

func capture_layers(folder: String, index: int) -> void:
	var vfx := deer.vfx
	var visibility: Dictionary = {}
	for child in vfx.get_children():
		if child is CanvasItem and not child.is_queued_for_deletion(): visibility[child] = child.visible
		if child is DeerPaintedEffect:
			visibility[child.back] = child.back.visible
			visibility[child.front] = child.front.visible
	body.texture = deer.animated_sprite.sprite_frames.get_frame_texture(deer.animated_sprite.animation, deer.animated_sprite.frame)
	body.position = deer.position + deer.animated_sprite.position
	body.scale = deer.animated_sprite.scale
	body.flip_h = deer.animated_sprite.flip_h
	# Original unshaded action pixels are the drawing reference; core glow remains
	# on the effect layer. The body never becomes translucent during this preview.
	viewport.canvas_transform = Transform2D(0, Vector2.ONE * WORLD_SCALE, 0, ANCHOR - deer.position * WORLD_SCALE)
	for layer in ["body", "back", "front", "warning"]:
		body.visible = layer == "body"
		vfx.visible = layer != "body"
		vfx.self_modulate.a = 1.0 if layer == "front" else 0.0
		for child in visibility:
			if not is_instance_valid(child): continue
			var include := false
			if child is DeerPaintedEffect: include = layer in ["back", "front"]
			elif child is Sprite2D and child.get_parent() is DeerPaintedEffect:
				include = layer == ("back" if child == child.get_parent().back else "front")
			elif child == vfx._vine_back or child == vfx._uppercut_back: include = layer == "back"
			elif child is DeerDustBurst: include = layer == ("back" if child.back_layer else "front")
			elif child == vfx.red_warning or child == vfx.gold_warning: include = layer == "warning"
			child.visible = visibility[child] and include
		vfx.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var error := viewport.get_texture().get_image().save_png(folder.path_join("%04d_%s.png" % [index, layer]))
		if error != OK:
			failed = true
			push_error("Capture failed: " + folder)
	vfx.self_modulate.a = 1.0
	for child in visibility:
		if is_instance_valid(child): child.visible = visibility[child]

func export_clip(kind: String, action: int, seconds: float) -> void:
	room.play_action(action)
	if kind == "vine_cage":
		for tick in 75: advance()
		if not room.use_preview_item():
			failed = true
			push_error("Could not start cage from the real counter window")
			return
	# The real timeline selects its first body pose on the first physics tick.
	# A negligible tick selects that pose before the first 50 ms sample.
	deer._physics_process(0.000001)
	var folder := output.path_join("raw").path_join(kind)
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	for index in ceili(seconds * FPS):
		var attack: String = String(deer.attack_hitbox.attack.attack_id) if deer.attack_hitbox.attack != null else ""
		frames.append({"index": index, "time_ms": index * 50, "duration_ms": 50,
			"stage": stage(kind), "animation": String(deer.animated_sprite.animation), "body_frame": deer.animated_sprite.frame,
			"world_position": [deer.position.x, deer.position.y], "direction": deer.direction,
			"attack": attack, "state": DeerBoss.State.keys()[deer.state], "segment": deer._segment,
			"snare_growth": deer.vfx._snare_growth})
		await capture_layers(folder, index)
		for tick in 3: advance()
	clips.append({"id": kind, "folder": folder, "frames": frames})
	print("EXPORTED ", kind, " ", frames.size(), " frames")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Pass an output directory after --")
		quit(1)
		return
	output = args[0]
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	deer = room.adapter.boss as DeerBoss
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.player.set_physics_process(false)
	room.set_physics_process(false)
	room.hide()
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	root.add_child(viewport)
	deer.vfx.reparent(viewport, false)
	body = Sprite2D.new()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(body)
	await export_clip("light_stomp", 0, 1.30)
	await export_clip("heavy_stomp", 1, 3.00)
	await export_clip("mist_combo", 2, 4.40)
	await export_clip("charge_uppercut", 3, 3.00)
	await export_clip("mist_ultimate", 4, 12.00)
	await export_clip("vine_cage", 4, 5.00)
	var manifest := {"canvas": [SIZE.x, SIZE.y], "anchor": [ANCHOR.x, ANCHOR.y],
		"world_units_per_pixel": 1.4, "fps": FPS, "source_scene": "res://scenes/dev/boss_development_room.tscn", "clips": clips}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	if FileAccess.file_exists(SaveProgressService.SAVE_PATH) != existed or (existed and FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) != saved):
		failed = true
		push_error("Export changed saved progress")
	deer.vfx.reparent(room.specimen, false)
	viewport.free()
	current_scene = null
	room.free()
	print("ART CAPTURE COMPLETE: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
