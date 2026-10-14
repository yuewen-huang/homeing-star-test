extends SceneTree
## Native runtime checks and optional Godot screenshots of the five-second intro.
var room
var twin: TwinFishBoss
var checks := 0
var failures := 0
var output := ""
var record_animation := false
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
	check(room.boss_picker.item_count == 4 and room.selected_boss == 2 and room.boss_picker.get_item_text(2).contains("双子"), "third picker option selects real TwinFishBoss")
	check(twin.manual_control and twin is BossBase and twin is DamageReceiver2D, "development twin uses shared combat contract with AI disabled")
	check(twin.white_data.source == "双子白-walk.aseprite" and twin.black_data.source == "双子黑-walk.aseprite", "only the two requested authored walk sources are used")
	check(twin.white_data.duration_ms.size() == 16 and twin.black_data.duration_ms.size() == 16 and twin.black_data.source_depth == 8, "native 16-frame timing and indexed black palette are retained")
	check(twin.white_sprite.offset == Vector2(-128, -128) and twin.white_sprite.scale == Vector2.ONE * 1.4 and twin.black_sprite.scale == twin.white_sprite.scale, "full-canvas shared pivot and uniform art scale are retained")
	check(not twin.is_in_group(&"damageable") and twin.get_node("Hurtbox").collision_layer == 0, "specimen cannot be damaged by the observing player")
	check(not room.combo_button.visible and not room.charge_button.visible and not room.ultimate_row.visible and not room.segment_row.visible, "unimplemented attacks and deer-specific controls are hidden")
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
	check(absf(entry_a.distance_to(entry_b) - entry_b.distance_to(twin.white_sprite.position)) < 0.1, "entry cruises at uniform speed instead of easing down through the whole segment")
	check(twin.state == TwinFishBoss.State.ARRIVAL and twin.white_sprite.position.x > 0 and twin.black_sprite.position.x < 0, "first second brings both fish inward from opposite sides")
	check(twin.white_sprite.rotation == 0 and twin.black_sprite.rotation == 0 and not twin.white_sprite.flip_h and twin.black_sprite.flip_h, "entry stays horizontal and black fish mirrors without turning belly-up")
	var tail := twin.black_sprite.deformed_point(Vector2(80, 0))
	var head := twin.black_sprite.deformed_point(TwinFishSwimSprite.HEAD_POINT)
	var entry_frame := twin.black_frame
	to_time(0.65)
	check(twin.black_frame != entry_frame and twin.black_sprite.deformed_point(Vector2(80, 0)).distance_to(tail) > 0.5 and twin.black_sprite.deformed_point(TwinFishSwimSprite.HEAD_POINT).distance_to(head) < 0.001, "native swim frames and travelling tail wave advance while entry head stays stable")
	await capture("01_two_sides")
	to_time(1.02)
	check(twin.state == TwinFishBoss.State.CHASE, "1 second enters chasing state")
	check((twin.white_sprite.position + twin.black_sprite.position).length() < 0.01, "orbit phases differ by PI around the same center")
	check(twin.black_sprite.head_forward().dot(twin.white_sprite.head_forward()) < -0.999, "head-led fish have opposite tangent headings without a whole-sprite roll")
	var tangent := twin.white_trail.head_direction
	check(twin.white_sprite.head_forward().dot(tangent) > 0.99, "the rendered head follows the actual swimming tangent")
	to_time(1.3)
	var angle_a := twin.orbit_angle
	to_time(1.55)
	var angle_b := twin.orbit_angle
	to_time(1.8)
	check(twin.orbit_radius < TwinFishBoss.OPEN_RADIUS and absf((angle_b - angle_a) - (twin.orbit_angle - angle_b)) < 0.001, "chase contracts its orbit while maintaining a steady rotation rate")
	check(twin.white_sprite.follows_path and twin.black_sprite.follows_path and twin.white_sprite.skin.mesh != null, "both textured bodies follow head-path history instead of rigid pictures")
	check(twin.white_sprite.point_in_boss(TwinFishSwimSprite.HEAD_POINT).distance_to(twin.white_sprite.position) < 0.001, "head joint is anchored to the actual head path")
	await capture("02_chase")
	to_time(2.55)
	check(twin.state == TwinFishBoss.State.TAICHI and is_equal_approx(twin.orbit_radius, TwinFishBoss.TAICHI_RADIUS), "2.5 seconds forms the compact taichi arrangement")
	var frame := twin.white_frame
	var black_frame := twin.black_frame
	var angle := twin.orbit_angle
	to_time(3.1)
	check(twin.white_frame == frame and twin.black_frame == black_frame, "taichi freezes both authored swim poses")
	check(twin.orbit_angle > angle and twin.orbit_angle - angle < 0.2, "frozen taichi turns only gently")
	await capture("03_taichi")
	to_time(3.6)
	check(twin.state == TwinFishBoss.State.SUBMERGE and twin.dive_progress > 0.0, "3.5 seconds starts the dark-water dive")
	var at := twin.black_sprite.position
	var dive := twin.dive_progress
	var age := twin.arrival_age
	twin.advance_action(0.0)
	await process_frame
	await process_frame
	check(twin.arrival_age == age and twin.dive_progress == dive and twin.black_sprite.position == at, "pause freezes fish, water and Tween even across scene frames")
	to_time(4.01)
	check(twin.black_sprite.mirror_enabled and twin.black_sprite.modulate.a == 1.0 and twin.black_sprite.scale == Vector2.ONE * 1.4, "dive uses a spatial mirror mask without whole-fish fading or shrinking")
	check(twin.white_leaving and twin.handoff_blend < 0.02, "white begins its tangent departure at four seconds while black is still diving")
	await capture("04_dark_water")
	to_time(4.15)
	check(twin.black_sprite.point_in_boss(TwinFishSwimSprite.HEAD_POINT).y > TwinFishBoss.MIRROR_POSITION.y and twin.black_sprite.point_in_boss(Vector2(92, -6)).y < TwinFishBoss.MIRROR_POSITION.y, "head is below the mirror while the following tail is still above it")
	check(twin.white_sprite.head_forward().dot(Vector2.LEFT) > 0.99 and twin.white_sprite.position.x < 0 and twin.white_frame != frame, "white swims forward off the tangent and resumes its native swim frames")
	await capture("04b_head_under_tail_above")
	to_time(4.4)
	check(twin.black_sprite.visible and twin.black_sprite.modulate.a == 1.0 and twin._black_spine(230).y < TwinFishBoss.MIRROR_POSITION.y, "late dive still retains the tail until it physically reaches the mirror")
	await capture("05_mirror_entry")
	to_time(4.48)
	check(twin._black_spine(240).y > TwinFishBoss.MIRROR_POSITION.y, "the full visible black body clears the mirror before cleanup")
	to_time(4.7)
	check(twin.state == TwinFishBoss.State.UNFOLD and not twin.black_sprite.visible and twin.handoff_blend > 0, "4.5 seconds hides black fish and restores white posture")
	check(twin.white_path_distance > 130 and twin.white_sprite.head_forward().dot(Vector2.LEFT) > 0.99, "white heading and movement stay aligned throughout the overlap")
	await capture("06_white_unfold")
	to_time(4.99)
	check(twin.state == TwinFishBoss.State.UNFOLD and twin.phase == 0, "combat phase cannot start before the last half-second finishes")
	var before_handoff := twin.white_sprite.position
	var tail_before := twin._white_spine(220)
	to_time(5.02)
	check(twin.state == TwinFishBoss.State.PHASE_ONE and twin.phase == 1 and handoffs == 1, "5 seconds hands the same white sprite to the real phase-one state once")
	check(twin.white_sprite.position.distance_to(twin.phase_one_position) < 0.1 and twin.white_sprite.head_forward().dot(Vector2.LEFT) > 0.999, "phase-one station is the actual departure endpoint with a horizontal head")
	check(before_handoff.distance_to(twin.white_sprite.position) < 4.0 and tail_before.distance_to(twin._white_spine(220)) < 4.0, "state handoff cannot teleport the head or snap the tail straight")
	check(not twin.black_sprite.visible and is_zero_approx(twin.dive_progress) and twin.attack_hitbox.attack == null, "handoff leaves no dark-water effect or attack")
	var white_id := twin.white_sprite.get_instance_id()
	await capture("07_phase_one")
	frame = twin.white_frame
	twin.advance_action(0.35)
	check(twin.white_frame != frame and twin.white_sprite.get_instance_id() == white_id and handoffs == 1, "phase one resumes authored horizontal swimming without respawning the fish")
	check(room.dummy.contacts.is_empty() and room.player.combat_stats.health == 100 and not root.get_node("ParryQTE").active, "the entire entrance has no damage, dummy hit or contact QTE")
	room.play_action(0)
	check(twin.state == TwinFishBoss.State.ARRIVAL and twin.entry_blend == 0 and twin.black_sprite.visible and twin.black_sprite.modulate == Color.WHITE, "replay completely restores the two fish after the dive")
	var old_tween := twin._timeline
	room.play_action(0)
	check(not old_tween.is_valid() and twin._timeline.is_valid(), "repeated play kills the prior Tween instead of stacking timelines")
	room.heavy_button.pressed.emit()
	check(twin.state == TwinFishBoss.State.PHASE_ONE and twin._timeline == null and not twin.black_sprite.visible, "2 directly previews phase-one idle without a dangling arrival Tween")

	# Real automatic physics under the room's speed selector, rather than merely
	# scaling a fake preview timer.
	room.play_action(0)
	room.set_playback_speed(0)
	twin.set_physics_process(true)
	for i in 12: await physics_frame
	twin.set_physics_process(false)
	check(absf(twin.arrival_age - 0.05) < 0.009, "quarter-speed selector advances the real five-second intro by quarter action time")
	room.set_playback_speed(2)

	for cut in [0.4, 1.8, 2.8, 4.0, 4.8]:
		room.play_action(0)
		to_time(cut)
		var previous := twin
		old_tween = twin._timeline
		room.reset_room()
		await process_frame
		await process_frame
		freeze()
		check(not is_instance_valid(previous) and not old_tween.is_valid() and room.selected_boss == 2 and twin.state == TwinFishBoss.State.ARRIVAL, "R clears the whole specimen and replays from stage %.1f" % cut)
	check(room.specimen.find_children("WhiteFish", "Sprite2D", true, false).size() == 1 and room.specimen.find_children("BlackFish", "Sprite2D", true, false).size() == 1, "resets retain exactly one fish pair under the current specimen")
	for cut in [0.6, 3.0, 4.1]:
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
	check(room.player.dodge_evaded_attack.get_connections().size() <= 1, "switching never accumulates shared player combat callbacks")
	room.play_action(0)
	to_time(4.0)
	old_tween = twin._timeline
	twin.combat_stats.apply_health_damage(twin.combat_stats.max_health)
	check(twin.state == TwinFishBoss.State.DEFEATED and twin._timeline == null and not old_tween.is_valid() and not twin.black_sprite.visible and twin.dive_progress == 0, "real death signal immediately clears the arrival Tween and dark-water effect")
	room.play_action(0)
	check(twin._mirror_surface.visible and twin.state == TwinFishBoss.State.ARRIVAL and not twin.black_sprite.mirror_enabled, "replay restores the mirror and clears the former underwater mask after cancellation")
	room.reset_room()
	await process_frame
	freeze()
	if record_animation:
		twin.start_arrival()
		for index_frame in 133:
			if index_frame > 0: twin.advance_action(1.0 / 24.0)
			await capture("movie_%03d" % index_frame)
	room.play_action(0)
	to_time(4.0)
	old_tween = twin._timeline
	room.free()
	current_scene = null
	await process_frame
	check(not old_tween.is_valid(), "leaving mid-dive also destroys the bound arrival Tween")
	check(Engine.time_scale == previous_speed, "leaving development room restores normal playback speed")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "arrival and all resets preserve story progress byte-for-byte")
	print("TWIN FISH ARRIVAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
