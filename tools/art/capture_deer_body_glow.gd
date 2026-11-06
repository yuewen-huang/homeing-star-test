extends "../../tests/support/harness.gd"
## Native forest comparison; no input automation or player save writes.

func capture(label: String) -> void:
	await wait_frames(2)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func run() -> void:
	use_memory_progress()
	var room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene = packed
	root.add_child(room)
	current_scene = room
	await wait_frames(4)
	room.player.reset_after_map_fall(Vector2(1250,555))
	room.player.set_physics_process(false)
	for stage in [1,2,3]:
		room.encounter._spawn_phase(stage,1450)
		room.encounter.start()
		await wait_frames(4)
		var boss = room.deer
		boss.manual_control = true
		boss.set_physics_process(false)
		boss.vfx.set_process(false)
		boss.direction = -1.0
		boss._sync_authored_body(&"idle_ING",.3)
		boss.vfx._clock = 1.0
		boss.vfx._sync_body_material()
		if stage == 1:
			boss.vfx._body_material.set_shader_parameter("body_fluorescence",0.0)
			boss.authored_body.set_glow(0.0,1.0)
			await capture("before")
			boss.vfx._sync_body_material()
		await capture("phase_%d_idle"%stage)
		if stage == 1:
			boss.vfx._clock = 2.6
			boss.vfx._sync_body_material()
			await capture("sheen")
			boss.direction = 1.0
			boss._sync_authored_body(&"bind_push_ING",.5)
			boss.vfx._sync_body_material()
			await capture("rush_right")
			boss.start_move(1,1250)
			for i in 100:
				boss._physics_process(1.0/60.0)
				boss.vfx._process(1.0/60.0)
				await physics_frame
				if i in [35,63,94]: await capture("drop_%03d"%i)
	room.queue_free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER BODY GLOW CAPTURE")
