extends SceneTree

var room
var failures := 0
var output := "D:/HomingStar/.artifacts/master-phase1-audit/game"

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames(2)
	room.select_boss(1)
	check(room.segment_picker.item_count == 19, "Eleven source actions and eight compound submoves exposed")
	check(room.segment_buttons[&"START"].disabled and not room.segment_buttons[&"ING"].disabled and room.segment_buttons[&"END"].disabled, "Idle keeps only its real loop segment")
	for index in MasterPhase1Art.preview_actions().size():
		room.select_segment_action(index)
		room.play_segment(&"ALL")
		var master = room.adapter.master
		var action: StringName = MasterPhase1Art.preview_actions()[index]
		check(master.animated_sprite.animation == action, "Real master previews " + action)
		check(master.animated_sprite.sprite_frames.get_frame_count(action) == MasterPhase1Art.FRAMES.get_frame_count(action), "Native frame count retained")
		await frames(55)
		await capture(String(action) + "_start")
		if action == &"air_spin_slam":
			await frames(40)
			await capture("air_spin_slam_airborne")
		await frames(300)
		check(master.attack_hitbox.attack == null and room.dummy.contacts.is_empty(), "Art preview has no combat damage")
		check(master.animated_sprite.frame == MasterPhase1Art.FRAMES.get_frame_count(action) - 1 and not master.animated_sprite.is_playing(), "Source clip ends held on final frame")
		check(room.adapter.action_sample().time < 4.0, "Telemetry measures authored seconds")
		await capture(String(action) + "_end")
		for part: String in MasterPhase1Art.parts(action):
			room.play_segment(StringName(part))
			var clip := StringName(String(action)+"_"+part)
			check(room.adapter.master.animated_sprite.animation == clip,"Segment button plays independent " + clip)
			var texture := room.adapter.master.animated_sprite.sprite_frames.get_frame_texture(clip,0) as AtlasTexture
			check(texture.atlas.resource_path.ends_with("/actions/"+String(clip)+".png"),"Segment reads its own physical PNG")
	for speed in [0, 1, 2]:
		room.set_playback_speed(speed)
		room.play_action(0)
		await frames(260 if speed == 0 else 140)
		check(not room.dummy.contacts.is_empty(), "Real attack contacts dummy at selected playback speed")
	room.play_action(1)
	await frames(25)
	await capture("attack2_warning")
	await frames(30)
	await capture("attack2_active")
	await frames(180)
	await capture("attack2_recovery")
	room.select_combo(1)
	check(not room.segment_row.visible, "Phase-two hides phase-one art tools")
	room.select_combo(0)
	check(room.segment_row.visible and room.segment_picker.item_count == 19, "Phase-one restores art tools")
	room.select_combo_library(2)
	room.play_action(4)
	await frames(40)
	room.reset_room()
	await frames(2)
	check(room.adapter.master.state == room.adapter.master.State.CHASE and room.specimen.get_child_count() == 2, "Reset clears airborne preview")
	room.queue_free()
	await frames(2)
	print("MASTER PHASE ONE ART failures: ", failures)
	quit(1 if failures else 0)
