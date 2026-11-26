extends SceneTree
## Native runtime checks and optional Godot captures of the entrance and free swim.
var room
var twin: TwinFishBoss
var checks := 0
var failures := 0
var output := ""
var record_animation := false
var capture_fps := 60
var handoffs := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func freeze() -> void:
	room.player.set_physics_process(false)
	twin = room.adapter.boss as TwinFishBoss
	twin.set_physics_process(false)

func to_time(seconds: float) -> void:
	twin.advance_action(maxf(0.0, seconds - twin.arrival_age))

func capture(label: String) -> void:
	if output.is_empty(): return
	room._process(0.0)
	room.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Godot capture " + label)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--visual-dir")
	if index >= 0 and DisplayServer.get_name() != "headless":
		output = args[index + 1]
		DirAccess.make_dir_recursive_absolute(output)
	record_animation = args.has("--capture-animation") and not output.is_empty()
	index = args.find("--capture-fps")
	if index >= 0: capture_fps = clampi(int(args[index + 1]), 1, 120)
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	var previous_speed := Engine.time_scale
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.boss_picker.item_selected.emit(2)
	await process_frame
	freeze()
	twin._swim_random.seed = 41019
	var twin_dodge_callbacks: int = room.player.dodge_evaded_attack.get_connections().size()
	check(room.selected_boss == 2 and room.boss_picker.get_item_text(2).contains("双子"), "third picker option selects real TwinFishBoss")
	check(twin.manual_control and twin is BossBase and twin is DamageReceiver2D, "development twin uses shared combat contract with AI disabled")
	check_shared_library()
	check_fixed_canvas_playback()
	check_turn_registration()
	check(twin.white_swimmer != twin.black_swimmer, "each fish owns an independent motion and action controller")
	check(twin.white_sprite.scale == Vector2.ONE * 0.91 and twin.black_sprite.scale == twin.white_sprite.scale, "both fish use the selected display scale")
	check(rig_is_valid(twin.white_sprite) and rig_is_valid(twin.black_sprite), "both fish show one procedural mesh with five combat guide bones")
	check(not twin.is_in_group(&"damageable") and twin.get_node("Hurtbox").collision_layer == 0, "specimen cannot be damaged by the observing player")
	check(room.combo_button.visible and room.combo_button.text.contains("演阵") and room.charge_button.visible and room.charge_button.text.contains("冲刺") and room.ultimate_row.visible and room.blade_button.visible and room.segment_row.visible and room.segment_picker.get_item_text(1).contains("破阵"), "the room offers the array showcase, lightning duet, thunder sea and playable Liangyi segment preview")
	check(not room.dummy.visible, "cinematic fish preview hides the non-attacking dummy so it cannot cover the fish")
	twin.phase_one_started.connect(func() -> void: handoffs += 1)
	room.light_button.pressed.emit()
	check(twin.state == TwinFishBoss.State.ARRIVAL and twin.arrival_age == 0.0 and twin.phase == 0, "1 restarts a clean real arrival")
	check(twin.white_sprite.global_position.x > 1280 and twin.black_sprite.global_position.x < 0, "fish begin outside opposite sides of the viewport")
	check(twin._timeline != null and twin._timeline.is_valid() and not twin._timeline.is_running(), "paused Tween is exclusively stepped by the boss action clock")
	to_time(0.15)
	var entry_a := twin.white_sprite.position
	to_time(0.30)
	var entry_b := twin.white_sprite.position
	to_time(0.45)
	check(entry_a.distance_to(entry_b) > entry_b.distance_to(twin.white_sprite.position), "the entrance gradually slows as the fish approach")
	check(twin.state == TwinFishBoss.State.ARRIVAL and twin.white_sprite.position.x > 0 and twin.black_sprite.position.x < 0, "first second brings both fish inward from opposite sides")
	check(twin.white_sprite.head_forward().dot(Vector2.LEFT) > 0.9 and twin.black_sprite.head_forward().dot(Vector2.RIGHT) > 0.9 and not twin.white_sprite.current_mirrored and twin.black_sprite.current_mirrored, "entry keeps both fish upright and facing into the room")
	var tail: Vector2 = twin.black_sprite.global_joints()[4] - twin.black_sprite.global_position
	var entry_frame: int = twin.black_sprite.current_frame
	to_time(0.65)
	var moved_tail: Vector2 = twin.black_sprite.global_joints()[4] - twin.black_sprite.global_position
	check(twin.black_sprite.current_frame != entry_frame and moved_tail.distance_to(tail) > 0.1 and source_points_are_preserved(), "swim frames and source bone markers advance without moving the shared canvas pivot")
	to_time(1.7)
	await capture("01_two_sides")
	await check_arrival_formation()
	to_time(TwinFishBoss.FREE_SWIM_TIME - 0.01)
	var before_white := travel_position(twin.white_swimmer)
	var before_black := travel_position(twin.black_swimmer)
	to_time(TwinFishBoss.FREE_SWIM_TIME + 0.01)
	check(twin.state == TwinFishBoss.State.SWIM_OUT and twin.black_sprite.visible and twin.white_sprite.visible, "both fish finish their authored recovery and continue into independent swimming")
	check(travel_position(twin.white_swimmer).distance_to(before_white) < 4.0 and travel_position(twin.black_swimmer).distance_to(before_black) < 4.0, "both action roots remain continuous as the fish swim apart")
	check(rig_is_valid(twin.white_sprite) and rig_is_valid(twin.black_sprite), "the approach-to-release handoff retains one procedural mesh per fish")
	var at := twin.black_sprite.position
	var age := twin.idle_age
	twin.advance_action(0.0)
	await process_frame
	await process_frame
	check(twin.idle_age == age and twin.black_sprite.position == at, "pause freezes the free swim across scene frames")
	to_time(TwinFishBoss.FREE_SWIM_TIME + 0.35)
	await capture("04_swimming_out")
	to_time(TwinFishBoss.ARRIVAL_TIME - 0.01)
	check(twin.state == TwinFishBoss.State.SWIM_OUT and twin.phase == 0, "both fish swim out before the phase handoff")
	before_white = travel_position(twin.white_swimmer)
	before_black = travel_position(twin.black_swimmer)
	to_time(TwinFishBoss.ARRIVAL_TIME + 0.02)
	check(twin.state == TwinFishBoss.State.PHASE_ONE and twin.phase == 1 and handoffs == 1, "the entrance enters the continuous idle once")
	check(before_white.distance_to(travel_position(twin.white_swimmer)) < 6.0 and before_black.distance_to(travel_position(twin.black_swimmer)) < 6.0, "state handoff keeps both action roots continuous")
	check(twin.black_sprite.visible and twin.find_child("MirrorSurface", false, false) == null and twin.attack_hitbox.attack == null, "the old mirror exit is gone and idle has no attack")
	check(twin._taichi_array.visible, "after the entrance the array remains behind the free swim")
	await check_free_swim()
	check(room.dummy.contacts.is_empty() and room.player.combat_stats.health == 100, "the entire entrance has no damage or dummy hit")
	room.play_action(0)
	check(twin.state == TwinFishBoss.State.ARRIVAL and twin.entry_blend == 0 and twin.black_sprite.visible and twin.black_sprite.modulate == Color.WHITE, "replay completely restores the entrance from idle")
	await check_taichi_array()
	var old_tween := twin._timeline
	room.play_action(0)
	check(not old_tween.is_valid() and twin._timeline.is_valid(), "repeated play kills the prior Tween instead of stacking timelines")
	room.heavy_button.pressed.emit()
	check(twin.state == TwinFishBoss.State.PHASE_ONE and twin._timeline == null and twin.black_sprite.visible and not twin._taichi_array.visible, "2 directly previews free swim and clears the entrance array")
	await check_array_evolution()

	# Real automatic physics under the room's speed selector, rather than merely
	# scaling a fake preview timer.
	room.play_action(0)
	room.set_playback_speed(0)
	twin.set_physics_process(true)
	for i in 12: await physics_frame
	twin.set_physics_process(false)
	check(absf(twin.arrival_age - 0.05) < 0.009, "quarter-speed selector advances the entrance by quarter action time")
	room.set_playback_speed(2)

	for cut in [0.4, 2.8, TwinFishBoss.ARRAY_FORM_TIME + 0.1, 6.7, TwinFishBoss.ARRIVAL_TIME + 0.1]:
		room.play_action(0)
		to_time(cut)
		var previous := twin
		old_tween = twin._timeline
		room.reset_room()
		await process_frame
		await process_frame
		freeze()
		check(not is_instance_valid(previous) and (old_tween == null or not old_tween.is_valid()) and room.selected_boss == 2 and twin.state == TwinFishBoss.State.ARRIVAL, "R clears the whole specimen and replays from stage %.1f" % cut)
	check(room.specimen.find_children("WhiteFish", "Node2D", true, false).size() == 1 and room.specimen.find_children("BlackFish", "Node2D", true, false).size() == 1, "resets retain exactly one fish pair under the current specimen")
	for cut in [0.6, 3.0, TwinFishBoss.SWIM_OUT_TIME + 0.3]:
		room.play_action(0)
		to_time(cut)
		var previous := twin
		old_tween = twin._timeline
		room.select_boss(1)
		await process_frame
		check(not is_instance_valid(previous) and not old_tween.is_valid() and room.selected_boss == 1, "switching to existing boss cancels twin stage %.1f" % cut)
		check(room.dummy.visible, "switching away from cinematic preview restores the shared dummy")
		room.select_boss(2)
		await process_frame
		freeze()
	check(room.player.dodge_evaded_attack.get_connections().size() == twin_dodge_callbacks, "switching never accumulates shared player combat callbacks")
	room.play_action(0)
	to_time(TwinFishBoss.SWIM_OUT_TIME + 0.3)
	old_tween = twin._timeline
	twin.combat_stats.apply_health_damage(twin.combat_stats.max_health)
	check(twin.state == TwinFishBoss.State.DEFEATED and twin._timeline == null and not old_tween.is_valid() and not twin.black_sprite.visible and not twin._taichi_array.visible, "real death signal cancels the swimming presentation and array")
	room.play_action(0)
	check(twin.state == TwinFishBoss.State.ARRIVAL and twin.black_sprite.visible, "replay restores both fish after cancellation")
	room.reset_room()
	await process_frame
	freeze()
	if record_animation:
		twin._swim_random.seed = 41019
		twin.start_arrival()
		for index_frame in 12 * capture_fps:
			if index_frame > 0: twin.advance_action(1.0 / float(capture_fps))
			await capture("movie_%03d" % index_frame)
	room.play_action(0)
	to_time(4.0)
	old_tween = twin._timeline
	room.free()
	current_scene = null
	await process_frame
	check(not old_tween.is_valid(), "leaving during the transition destroys the bound entrance Tween")
	check(Engine.time_scale == previous_speed, "leaving development room restores normal playback speed")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "arrival and all resets preserve story progress byte-for-byte")
	print("TWIN FISH ARRIVAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func travel_position(swimmer: TwinFishSwimmer) -> Vector2:
	# A one-time change of source canvas at a clip seam is not travel.
	return swimmer.position - swimmer.root_registration

func source_body_center(swimmer: TwinFishSwimmer) -> Vector2:
	var frame: Dictionary = twin.motion_data.frames[swimmer.frame_index]
	var center := (Vector2(frame.joints[1][0], frame.joints[1][1]) + Vector2(frame.joints[2][0], frame.joints[2][1])) * 0.5
	center -= Vector2(twin.motion_data.canvas[0], twin.motion_data.canvas[1]) * 0.5
	if swimmer.mirrored: center.x = -center.x
	return swimmer.position + center.rotated(swimmer.body_rotation) * TwinFishBoss.WORLD_SCALE

func check_turn_registration() -> void:
	# Registration is permitted once when changing the source clip. Every
	# subsequent frame must retain the source canvas and its original motion.
	var step := 1.0 / 120.0
	for upward in [false, true]:
		for facing_right in [false, true]:
			var swimmer := TwinFishSwimmer.new()
			var partner := TwinFishSwimmer.new()
			swimmer.configure(twin.motion_data, 0, TwinFishBoss.WORLD_SCALE)
			partner.configure(twin.motion_data, 1, TwinFishBoss.WORLD_SCALE)
			var direction := Vector2.RIGHT if facing_right else Vector2.LEFT
			swimmer.reset(Vector2(30.0, 10.0), direction)
			partner.reset(Vector2(10000.0, 10000.0), direction)
			check(swimmer.root_registration == Vector2.ZERO, "turn probe starts with cleared registration")
			swimmer.start_turn(upward)
			var registration_changes := 0
			var before_frames := {}
			var after_frames := {}
			var aligned := true
			var integrated := true
			var change_on_new_drawing := true
			var samples := 0
			var expected_sign := (1.0 if upward else -1.0) * (-1.0 if facing_right else 1.0)
			var direction_consistent := true
			var total_turn := 0.0
			var peak_turn_rate := 0.0
			while swimmer.turning and samples < 1200:
				var old_registration := swimmer.root_registration
				var old_frame := swimmer.frame_index
				var old_mirror := swimmer.mirrored
				var old_center := source_body_center(swimmer)
				var old_travel := travel_position(swimmer)
				var old_heading := swimmer.heading
				var old_painted_heading := swimmer._frame_head(swimmer.frame_index, swimmer.mirrored)
				swimmer.advance(step, swimmer.position + direction * 300.0, 100.0, partner)
				var turn_step := angle_difference(old_heading, swimmer.heading)
				var painted_step := angle_difference(old_painted_heading, swimmer._frame_head(swimmer.frame_index, swimmer.mirrored))
				direction_consistent = direction_consistent and turn_step * expected_sign >= -0.0001 and painted_step * expected_sign >= -0.0001
				total_turn += turn_step
				peak_turn_rate = maxf(peak_turn_rate, absf(turn_step) / step)
				var changed := swimmer.root_registration.distance_to(old_registration) > 0.00001
				if changed:
					registration_changes += 1
					aligned = aligned and source_body_center(swimmer).distance_to(old_center) <= swimmer.speed * step + 0.1
					change_on_new_drawing = change_on_new_drawing and (old_frame != swimmer.frame_index or old_mirror != swimmer.mirrored)
				integrated = integrated and travel_position(swimmer).distance_to(old_travel) <= swimmer.speed * step + 0.001
				var key := "%d/%s" % [swimmer.frame_index, swimmer.mirrored]
				if registration_changes == 0: before_frames[key] = true
				else: after_frames[key] = true
				samples += 1
			var label := "turn %s facing %s" % ["up" if upward else "down", "right" if facing_right else "left"]
			check(not swimmer.turning and registration_changes == 1 and change_on_new_drawing and before_frames.size() >= 2 and after_frames.size() >= 2, label + " registers exactly once between clips and retains that registration across subsequent drawings")
			check(aligned and integrated, label + " preserves the world body center at its seam while continuous travel remains bounded by velocity")
			check(direction_consistent and absf(total_turn * expected_sign - PI) < 0.001, label + " keeps both painted and travel turns in one direction through the full half-turn")
			check(peak_turn_rate <= deg_to_rad(301.0), label + " bounds the source action's angular playback rate without rotating the sprite")
			swimmer.reset(Vector2.ZERO, direction)
			check(swimmer.root_registration == Vector2.ZERO, label + " clears registration on replay")

func rig_is_valid(sprite: TwinFishRigSprite) -> bool:
	return sprite.visible and sprite.bones.size() == 5 and is_instance_valid(sprite.skeleton) and sprite.skin == null and sprite.procedural_body.body_texture != null and sprite.find_children("*", "MeshInstance2D", true, false).size() == 1

func source_points_match(sprite: TwinFishRigSprite) -> bool:
	var canvas := Vector2(twin.motion_data.canvas[0], twin.motion_data.canvas[1])
	var pivot := canvas * 0.5
	if sprite.skeleton.position.length() > 0.001: return false
	var side := -1.0 if sprite.current_mirrored else 1.0
	if sprite.skeleton.scale.distance_to(Vector2(side, 1.0)) > 0.001: return false
	var source: Array = twin.motion_data.frames[sprite.current_frame].joints
	var joints: PackedVector2Array = sprite.global_joints()
	if joints.size() != source.size(): return false
	for index in source.size():
		var point := Vector2(source[index][0], source[index][1]) - pivot
		point.x *= side
		var expected := sprite.global_transform * point.rotated(sprite.skeleton.rotation)
		if joints[index].distance_to(expected) > 0.001: return false
	return true

func source_points_are_preserved() -> bool:
	return source_points_match(twin.white_sprite) and source_points_match(twin.black_sprite)

func check_fixed_canvas_playback() -> void:
	# Run each complete original curl in isolation with an immobile world root.
	# This catches frame-wise head anchoring even if live motion hides its drift.
	for sprite in [twin.white_sprite, twin.black_sprite]:
		var original_transform: Transform2D = sprite.transform
		var original_frame: int = sprite.current_frame
		var original_mirror: bool = sprite.current_mirrored
		var original_rotation: float = sprite.skeleton.rotation
		sprite.position = Vector2(37.0, -29.0)
		var fixed_root: Vector2 = sprite.global_position
		for clip_name in ["high_curl", "low_curl"]:
			var clip: Dictionary = twin.motion_data.clips[clip_name]
			for mirrored in [false, true]:
				for body_rotation in [0.0, 0.23]:
					var exact := true
					var root_still := true
					var head_min := Vector2.INF
					var head_max := -Vector2.INF
					var body_min := Vector2.INF
					var body_max := -Vector2.INF
					for frame in int(clip.count):
						sprite.show_pose(int(clip.first) + frame, mirrored, body_rotation, 1.0 / 12.0, frame == 0)
						exact = exact and source_points_match(sprite) and absf(sprite.skeleton.rotation - body_rotation) < 0.001
						root_still = root_still and sprite.global_position.distance_to(fixed_root) < 0.001
						var points: PackedVector2Array = sprite.global_joints()
						var head: Vector2 = sprite.to_local(points[0])
						var body: Vector2 = sprite.to_local(points[2])
						head_min = head_min.min(head)
						head_max = head_max.max(head)
						body_min = body_min.min(body)
						body_max = body_max.max(body)
					var label := "%s %s mirror=%s rotation=%.2f" % [sprite.name, clip_name, mirrored, body_rotation]
					check(exact and root_still, label + " keeps the canvas root and offset fixed while preserving every original joint")
					check(head_min.distance_to(head_max) > 60.0 and body_min.distance_to(body_max) > 30.0, label + " retains the head and body's authored movement within the cell")
		sprite.transform = original_transform
		sprite.show_pose(original_frame, original_mirror, original_rotation, 0.0, true)

func check_shared_library() -> void:
	var data: Dictionary = twin.motion_data
	for clip in ["high_curl", "low_curl"]:
		check(absf(twin.white_swimmer.clip_duration(clip) - TwinFishBoss.CURL_TIME) < 0.001, clip + " finishes its retimed source frames at the entrance handoff")
	check(data.frames.size() == 240 and data.clips.size() == 8 and data.columns == 8, "the shared motion library contains the native swim and all seven complete actions")
	var valid := true
	for frame in data.frames:
		valid = valid and frame.joints.size() == 5 and is_finite(float(frame.heading_deg))
		for point in frame.joints:
			valid = valid and point.size() == 2 and is_finite(float(point[0])) and is_finite(float(point[1]))
	check(valid, "every source frame has the same five-joint pose description and a finite heading")
	var covered := {}
	for name in data.clips:
		var clip: Dictionary = data.clips[name]
		for index in int(clip.count): covered[int(clip.first) + index] = true
	check(covered.size() == data.frames.size() and covered.has(0) and covered.has(239), "the shared action index covers every packed source frame")
	check(twin.white_sprite.procedural_body.body_texture != twin.black_sprite.procedural_body.body_texture and twin.white_sprite.procedural_body.body_texture.get_size() == twin.black_sprite.procedural_body.body_texture.get_size(), "each fish uses its own straight texture")

func capture_bones(label: String) -> void:
	if output.is_empty(): return
	twin.white_sprite.debug_bones = true
	twin.black_sprite.debug_bones = true
	await capture(label)
	twin.white_sprite.debug_bones = false
	twin.black_sprite.debug_bones = false

func check_taichi_array() -> void:
	var array := twin._taichi_array
	to_time(TwinFishBoss.ARRAY_FORM_TIME - 0.02)
	check(not array.visible, "the array stays hidden while the fish approach")
	to_time(TwinFishBoss.ARRAY_FORM_TIME + 0.04)
	var white := twin.white_sprite.position
	var black := twin.black_sprite.position
	var white_core := twin.white_sprite.joint_in_boss(1).lerp(twin.white_sprite.joint_in_boss(2), 0.35)
	var black_core := twin.black_sprite.joint_in_boss(1).lerp(twin.black_sprite.joint_in_boss(2), 0.35)
	var at := array.position
	var poles := array.active_core_positions()
	var held_size: Vector2 = array._circle.size
	check(twin.white_frame == 189 and twin.black_frame == 32, "the array reveals on the reference pose, with the curled white fish high right and the black fish low left")
	check(array.visible and array.stage == 2.0 and poles.size() == 2 and array.to_global(poles[1]).is_equal_approx(twin.to_global(white_core)) and array.to_global(poles[0]).is_equal_approx(twin.to_global(black_core)), "each original Liangyi pole aligns to its own fish at the held pose")
	check(array.get_index() < twin.black_sprite.get_index() and array.z_index <= twin.black_sprite.z_index and array.z_index < twin.white_sprite.z_index, "the array draws behind both fish")
	to_time(TwinFishBoss.SWIM_OUT_TIME - 0.03)
	check(twin.white_sprite.position == white and twin.black_sprite.position == black and array.active_core_positions() == poles and is_equal_approx(array.modulate.a, 1.0), "both fish and the two poles hold the fully revealed pose before release")
	await capture("taichi_hold")
	to_time(TwinFishBoss.SWIM_OUT_TIME + 0.65)
	var turned := array.active_core_positions()
	var pole_turn := angle_difference((poles[0] / held_size).angle(), (turned[0] / array._circle.size).angle())
	check(twin.white_sprite.position.distance_to(white) > 30.0 and twin.black_sprite.position.distance_to(black) > 30.0 and array.position.distance_to(array.resting_center()) < at.distance_to(array.resting_center()) and pole_turn < 0.0, "both fish swim away while the circle turns and rises toward its ground-aligned center")
	await capture("taichi_release")
	twin.advance_action(0.0)
	await process_frame
	check(array.active_core_positions() == turned, "the array pauses with the action clock")
	to_time(TwinFishBoss.SWIM_OUT_TIME + array.OPEN_TIME + 0.02)
	var area := array.battlefield_rect()
	var paint := array.painted_bounds()
	check(array._circle.size.is_equal_approx(array.field_size()) and array._circle.size.x == array._circle.size.y and array.scale == Vector2.ONE, "the entrance fits a circle within the reserved battlefield height")
	check(is_equal_approx(paint.end.y, area.end.y) and paint.position.y >= area.position.y - 0.01, "the outer circle meets the floor and stays below the battlefield ceiling")

func check_array_evolution() -> void:
	room.combo_button.pressed.emit()
	var array := twin._taichi_array
	check(array.visible and array.playing_evolution and array.stage == 0.0, "3 begins the full array sequence in the development room")
	check(array._circle.size.is_equal_approx(array.field_size()) and array._circle.size.x == array._circle.size.y and is_equal_approx(array.painted_bounds().end.y, array.battlefield_rect().end.y), "the full array uses the same ground-aligned circle in the development room")
	var elapsed := 0.0
	for phase in 4:
		var settled: float = array.STAGE_ENDS[phase] + 0.20
		twin.advance_action(settled - elapsed)
		elapsed = settled
		check(is_equal_approx(array.stage, float(phase + 1)), "the full sequence settles on stage %d at the original cue" % (phase + 1))
		await capture("ritual_stage_%d" % (phase + 1))
	var cardinals := array.active_core_positions()
	check(cardinals.size() == 8 and cardinals[0].dot(Vector2.UP) > 0.0 and absf(cardinals[0].x) < 0.01 and cardinals[2].dot(Vector2.RIGHT) > 0.0 and absf(cardinals[2].y) < 0.01, "the packaged Bagua keeps all eight gates on the project axes")
	twin.advance_action(0.4)
	check(array.active_core_positions() == cardinals, "project Bagua directions stay fixed while the field continues to animate")
	room.heavy_button.pressed.emit()
	check(not array.visible and not array.playing_evolution, "switching to free swim clears the full array sequence")

func check_arrival_formation() -> void:
	to_time(TwinFishBoss.GLIDE_TIME - 0.01)
	var last_positions := [travel_position(twin.white_swimmer), travel_position(twin.black_swimmer)]
	var last_headings := [twin.white_sprite.head_forward(), twin.black_sprite.head_forward()]
	var last_frames := [twin.white_sprite.current_frame, twin.black_sprite.current_frame]
	var hold_times := [0.0, 0.0]
	var maximum_hold := 0.0
	var continuous_roots := true
	var continuous_headings := true
	var source_preserved := true
	var single_sprite := true
	var frames := [{}, {}]
	var minimum_body_separation := INF
	var gather_capture := false
	var before_capture := false
	var meeting_capture := false
	var after_capture := false
	var release_capture := false
	var passage := TwinFishBoss.SWIM_OUT_TIME - TwinFishBoss.TAICHI_START
	var before_time := TwinFishBoss.TAICHI_START + passage * 0.2
	var meeting_time := TwinFishBoss.TAICHI_START + passage * 0.5
	var after_time := TwinFishBoss.TAICHI_START + passage * 0.8
	# Ignore only the explicitly timed array pose when checking the normal frame cadence.
	var brake_start := TwinFishBoss.ARRAY_FORM_TIME - TwinFishBoss.ARRAY_RAMP_TIME
	var resume_end := TwinFishBoss.SWIM_OUT_TIME + TwinFishBoss.ARRAY_RAMP_TIME
	while twin.arrival_age < TwinFishBoss.FREE_SWIM_TIME - 0.0101:
		var step := minf(1.0 / 60.0, TwinFishBoss.FREE_SWIM_TIME - 0.01 - twin.arrival_age)
		twin.advance_action(step)
		var sprites := [twin.white_sprite, twin.black_sprite]
		source_preserved = source_preserved and source_points_are_preserved()
		for i in 2:
			var sprite: TwinFishRigSprite = sprites[i]
			var swimmer: TwinFishSwimmer = twin.white_swimmer if i == 0 else twin.black_swimmer
			var moved: Vector2 = travel_position(swimmer) - last_positions[i]
			continuous_roots = continuous_roots and moved.length() < 6.0
			continuous_headings = continuous_headings and absf(last_headings[i].angle_to(sprite.head_forward())) < deg_to_rad(65.0)
			single_sprite = single_sprite and rig_is_valid(sprite)
			frames[i][sprite.current_frame] = true
			var array_pause := twin.arrival_age >= brake_start and twin.arrival_age <= resume_end
			hold_times[i] = hold_times[i] + step if last_frames[i] == sprite.current_frame and not array_pause else step
			maximum_hold = maxf(maximum_hold, hold_times[i])
			last_frames[i] = sprite.current_frame
			last_positions[i] = travel_position(swimmer)
			last_headings[i] = sprite.head_forward()
		var white_joints: PackedVector2Array = sprites[0].global_joints()
		var black_joints: PackedVector2Array = sprites[1].global_joints()
		minimum_body_separation = minf(minimum_body_separation, white_joints[2].distance_to(black_joints[2]))
		if not gather_capture and twin.arrival_age >= lerpf(TwinFishBoss.GATHER_START, TwinFishBoss.TAICHI_START, 0.5):
			gather_capture = true
			await capture("02_painted_gather")
		if not before_capture and twin.arrival_age >= before_time:
			before_capture = true
			await capture("03_before")
		if not meeting_capture and twin.arrival_age >= meeting_time:
			meeting_capture = true
			await capture("03_taichi")
			await capture_bones("03_taichi_bones")
		if not after_capture and twin.arrival_age >= after_time:
			after_capture = true
			await capture("03_after")
		if not release_capture and twin.arrival_age >= lerpf(TwinFishBoss.SWIM_OUT_TIME, TwinFishBoss.FREE_SWIM_TIME, 0.5):
			release_capture = true
			await capture("04_authored_release")
	check(continuous_roots and continuous_headings, "both fish preserve continuous action-root motion and bounded orientation changes through approach and release")
	check(source_preserved and single_sprite, "both fish retain the fixed canvas pivot and all original joint motion in a single undeformed sprite")
	check(maximum_hold <= 0.15, "outside the array pose the paired movement holds no source drawing for more than 0.15 seconds")
	check(minimum_body_separation > 45.0, "the two body cores remain distinct while meeting and swimming apart")
	check(frames[0].size() >= 20 and frames[1].size() >= 20, "both fish advance through their source actions during the meeting")

func check_free_swim() -> void:
	var minima := [Vector2.INF, Vector2.INF]
	var maxima := [-Vector2.INF, -Vector2.INF]
	var frames := [{}, {}]
	var actions := [{}, {}]
	var turns := [0, 0]
	var continuous := true
	var source_preserved := true
	var single_skin := true
	var in_water := true
	var independently_moving := false
	var independently_animated := false
	var nearest := INF
	var farthest := 0.0
	for sample in 480:
		var last := [travel_position(twin.white_swimmer), travel_position(twin.black_swimmer)]
		twin.advance_action(0.05)
		var sprites := [twin.white_sprite, twin.black_sprite]
		var swimmers := [twin.white_swimmer, twin.black_swimmer]
		source_preserved = source_preserved and source_points_are_preserved()
		var separation: float = sprites[0].position.distance_to(sprites[1].position)
		nearest = minf(nearest, separation)
		farthest = maxf(farthest, separation)
		independently_moving = independently_moving or swimmers[0].velocity.distance_to(swimmers[1].velocity) > 15.0
		independently_animated = independently_animated or swimmers[0].action_name != swimmers[1].action_name or absf(swimmers[0].action_age - swimmers[1].action_age) > 0.15
		for i in 2:
			var sprite: TwinFishRigSprite = sprites[i]
			var at := sprite.position
			minima[i] = minima[i].min(at)
			maxima[i] = maxima[i].max(at)
			frames[i][sprite.current_frame] = true
			actions[i][swimmers[i].action_name] = true
			if swimmers[i].turning: turns[i] += 1
			continuous = continuous and last[i].distance_to(travel_position(swimmers[i])) < 15.0
			single_skin = single_skin and rig_is_valid(sprite)
			in_water = in_water and at.x > -400.0 and at.x < 400.0 and at.y > -160.0 and at.y < 160.0
		if sample % 80 == 0:
			await capture("swim_%02d" % sample)
			if sample == 160: await capture_bones("swim_both_bones")
	if not in_water: print("SWIM BOUNDS: ", minima, " to ", maxima)
	check(in_water and twin.state == TwinFishBoss.State.PHASE_ONE and handoffs == 1, "both independent fish remain in the preview water through 24 seconds of pursuit")
	check(continuous and source_preserved and single_skin, "free swimming preserves both fixed canvas pivots, authored joint motion and continuous action roots")
	check(independently_moving and independently_animated and farthest - nearest > 35.0, "the pair has independent velocity, action progress and changing following distance")
	check(maxima[0].x - minima[0].x > 300.0 and maxima[1].x - minima[1].x > 300.0 and maxima[0].y - minima[0].y > 50.0 and maxima[1].y - minima[1].y > 50.0, "both fish traverse and change depth rather than staying in a fixed orbit")
	check(frames[0].size() > 24 and frames[1].size() > 24 and actions[0].size() >= 2 and actions[1].size() >= 2 and turns[0] > 0 and turns[1] > 0, "both fish select multiple shared actions and perform authored turns during pursuit")
