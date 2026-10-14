extends SceneTree
## Verify the actual master timelines and capture warning/active/recovery states
## in the shared development room without writing story progress.

var output := ""
var room
var master
var failures := 0
var checks := 0
var manifest: Dictionary

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	manifest = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join("接入校验.json")))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	print("PASS " if ok else "FAIL ", message)

func pose(action: StringName, at: float, facing := 1.0) -> void:
	master.combat_timeline.stop()
	master.position.x = 510
	room.player.position.x = 70
	master.danger_warning.stop()
	master.danger_warning.hide()
	master.movement_direction = facing
	master._start_attack(action)
	if action == &"dash" and at > 0.601:
		# Let the real vanish lock an on-screen destination, then move the
		# observer clear before the hitbox opens (no contact-assist pause).
		room.player.position.x = 620 if facing > 0 else 430
		master.combat_timeline.advance(0.501)
		await process_frame
		room.player.position.x = 70
		master.combat_timeline.advance(at - 0.501)
	else:
		master.combat_timeline.advance(at)
	await process_frame
	await process_frame
	# Body/effect time is driven manually. Sample the warning's independent
	# 16 FPS animation at the same action time instead of freezing frame 0.
	if master.danger_warning.visible:
		var animation: Animation = master.combat_timeline.get_animation(action)
		var warning_at := -1.0
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_METHOD:
				continue
			for key in animation.track_get_key_count(track):
				if animation.method_track_get_name(track, key) == &"_timeline_warning" \
				and animation.track_get_key_time(track, key) <= at:
					warning_at = animation.track_get_key_time(track, key)
		var warning_frame := floori((at - warning_at) * master.WARNING_FPS)
		if warning_frame >= master.WARNING_FRAME_COUNT or warning_at < 0:
			master.danger_warning.hide()
		else:
			master.danger_warning.frame = warning_frame
	master.danger_warning.pause()
	master.animated_sprite.pause()
	master.wind_effect.pause()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(name + ".png"))
	print("CAPTURE ", name)

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	await process_frame
	master = room.adapter.master
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	room.player.position.x = 70
	master.position.x = 510
	master.set_process(false)
	master.set_physics_process(false)
	master.combat_timeline.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for action: String in ["attack_1", "attack_2", "attack_3"]:
		for record: Dictionary in manifest.hitboxes[action]:
			var frame := int(record.frame)
			await pose(StringName(action), (frame - 1) * 0.1 + 0.001)
			var expected_position := Vector2(record.position[0], record.position[1])
			var expected_size := Vector2(record.size[0], record.size[1])
			check(master.animated_sprite.frame == frame - 1 and master.wind_effect.frame == frame - 1,
				"%s frame %d body/effect stay synchronized" % [action, frame])
			check(master.attack_hitbox.position.is_equal_approx(expected_position),
				"%s frame %d edited hitbox position" % [action, frame])
			check(master.attack_collision_shape.shape.size.is_equal_approx(expected_size),
				"%s frame %d edited hitbox size" % [action, frame])
			check(master.attack_hitbox.attack != null, "%s frame %d attack remains active" % [action, frame])
			await shot("%s_F%02d_edited" % [action, frame - 1])
	# Updating the rectangle within the same strike must not reset its hit set.
	await pose(&"attack_1", 0.801)
	var attack = master.attack_hitbox.attack
	master.attack_hitbox.hit_targets[123456] = true
	master.combat_timeline.advance(0.1)
	await process_frame
	check(master.attack_hitbox.attack == attack and master.attack_hitbox.hit_targets.has(123456),
		"Attack-1 frame updates keep one strike and its already-hit set")
	for sample in [
		[&"attack_1", 0.701, 0.801, 1.301],
		[&"attack_2", 1.401, 1.501, 2.401],
		[&"attack_3", 0.301, 0.501, 2.501],
		[&"dash", 0.501, 0.801, 1.301],
		[&"special_attack", 0.901, 1.201, 1.551],
	]:
		for stage in 3:
			await pose(sample[0], sample[stage + 1])
			await shot("%s_%s" % [sample[0], ["warning", "active", "recovery"][stage]])
		await pose(sample[0], sample[2], -1.0)
		check(master.wind_effect.scale.x < 0.0 if sample[0] != &"special_attack" else master.wind_effect.scale.x > 0.0,
			"%s retains original mirrored-facing convention" % sample[0])
		await shot("%s_active_left" % sample[0])
	var summary := "%d checks, %d failures" % [checks, failures]
	FileAccess.open(output.path_join("Godot校验.txt"), FileAccess.WRITE).store_string(summary)
	print(summary)
	quit(failures)
