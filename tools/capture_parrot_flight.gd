extends "../tests/support/harness.gd"
## Native review of both real forest appearances; never writes player progress.
var room: Chapter1WindRoom
var output: String

func capture_loop(bird: Sprite2D, update: Callable, label_name: String) -> void:
	var poses := [0.02,0.06,0.10,0.14,0.19,0.25,0.31,0.37]
	var seen := {}
	for i in poses.size():
		update.call(poses[i])
		seen[bird.frame]=true
		for n in 2: await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var center := bird.get_global_transform_with_canvas().origin
		var crop := Rect2i(Vector2i(center)-Vector2i(96,72),Vector2i(192,144))
		check(Rect2i(Vector2i.ZERO,picture.get_size()).encloses(crop),label_name+" pose stays inside the native viewport")
		picture.get_region(crop).save_png(output.path_join("%s_%02d.png" % [label_name,i]))
		if i==0: picture.save_png(output.path_join(label_name+"_context.png"))
	check(seen.size()==8,label_name+" renders the entire eight-pose wingbeat")

func run() -> void:
	var progress := use_memory_progress()
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	room=load("res://scenes/levels/chapter_1/chapter_1_wind_room.tscn").instantiate()
	root.add_child(room)
	current_scene=room
	for i in 4: await process_frame
	room.set_physics_process(false)
	room.set_process(false)
	room.player.set_physics_process(false)
	room._combat_parrot.set_process(false)
	room.camera.position_smoothing_enabled=false
	room.camera.limit_left=-10000
	room.camera.limit_right=10000
	room.camera.limit_top=-10000
	room.camera.limit_bottom=10000
	room.camera.position=room._combat_parrot.global_position+Vector2(0,100)
	for layer in root.find_children("*","CanvasLayer",true,false): layer.visible=false
	await capture_loop(room._combat_parrot._sprite,room._combat_parrot._apply_pose,"ambient")
	check(WindSteleParrot.flight_frame(0.02)==WindSteleParrot.flight_frame(0.42),"Wingbeat loops without an extra terminal frame")
	progress.set_stele_state(Chapter1WindRoom.COMBAT_ID,MinigameStele.SteleState.UNLOCKED)
	room.player.reset_after_map_fall(Vector2(room.arena_rect.get_center().x,room.get_node("Terrain/Arena").position.y))
	room._challenge(Chapter1WindRoom.COMBAT_ID,MinigameStele.SteleKind.COMBAT)
	var trial := room._combat_trial
	check(is_instance_valid(trial),"The existing combat trial still starts")
	room.camera.position=trial._bird.global_position+Vector2(0,100)
	await capture_loop(trial._bird,func(t: float):
		trial._age=t
		trial._update_bird_visual(),"trial")
	var before := trial._bird.frame
	trial.step(0.0)
	check(trial._bird.frame==before,"Zero action time preserves the trial wing pose")
	room.end_combat(false)
	check(room._combat_parrot.visible,"Ambient bird returns after the trial")
	expect_save_untouched()
	room.queue_free()
	for i in 3: await process_frame
	finish("PARROT FLIGHT NATIVE")
