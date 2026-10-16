extends SceneTree

var room
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale / 60.0
		room.adapter.deer._physics_process(delta)
		room._physics_process(delta)
		room.adapter.deer.vfx._process(delta)

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0.0)
	room.adapter.deer.vfx.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
		DirAccess.make_dir_recursive_absolute(output)
	var save_path := "res://save/progress.cfg"
	var had_save := FileAccess.file_exists(save_path)
	var save_before := FileAccess.get_file_as_bytes(save_path) if had_save else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.select_combo(2)
	check(deer.phase == 3 and room.combo_button.visible and room.charge_button.visible and room.ultimate_row.visible and room.item_button.visible and room.item_button.text == "种下定风桩 · Q", "Wind exposes pressure, flick, combo and the current wind-stake preview control")
	var health_before: int = room.player.combat_stats.health
	for action: String in DeerActionLibrary.clips():
		for frame in int(DeerActionLibrary.clip(StringName(action)).count):
			deer._show_clip(StringName(action), frame)
			check(deer.core_offset().is_finite(), "%s F%d has a usable chest anchor" % [action, frame])
	room.play_action(0)
	check(deer.can_be_interrupted_by_special(), "Ordinary clash action keeps the existing special-interrupt opportunity")
	tick(25)
	check(room.dummy.contacts.is_empty() and deer.attack_hitbox.attack == null, "Thrust windup cannot damage the dummy")
	await snapshot("thrust_left_windup")
	tick(10)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].first_frame == 1, "Thrust first contacts on authored forward F07")
	check(deer.attack_hitbox.attack.danger_type == CombatAttackData.DangerType.NORMAL, "Thrust uses existing ordinary attack semantics")
	await snapshot("thrust_left_contact")
	tick(27)
	check(deer.attack_hitbox.attack == null and room.dummy.contacts.size() == 1 and room.dummy.contacts[0].last_frame == 3, "Thrust closes after F09 and settles only once")
	await snapshot("thrust_left_recovery")
	tick(100)
	check(deer.state == DeerBoss.State.IDLE, "Thrust completes in manual idle")
	room.play_action(1)
	check(not deer.can_be_interrupted_by_special(), "Red finisher keeps its committed danger windup")
	tick(35)
	check(deer.vfx.red_warning.visible and room.dummy.contacts.is_empty(), "Red antler cue appears before contact")
	check(deer.vfx.red_warning.position.distance_to(deer.vfx.chest().snapped(Vector2(2,2))) < 0.01, "Red cue plays on the chest light, like every danger cue")
	await snapshot("red_left_warning")
	tick(20)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].first_frame == 0, "Red finisher first contacts on F11")
	check(deer.attack_hitbox.attack.danger_type == CombatAttackData.DangerType.COUNTERABLE_DANGER, "Finisher uses existing red counter semantics")
	await snapshot("red_left_contact")
	tick(120)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].last_frame == 2 and deer.attack_hitbox.attack == null, "Red finisher has one segment through F13")
	for target in [688, 1000]:
		room.dummy_x.value = target
		room.play_action(2)
		tick(300)
		check(room.dummy.contacts.size() == 3, "Three cuts reach the dummy in direction %d" % deer.direction)
		if room.dummy.contacts.size() == 3:
			var hits: Array = room.dummy.contacts
			check(hits.all(func(hit: Dictionary) -> bool: return hit.clip == "bind_push_ING"), "All quick cuts keep the authored low horn stance")
			check(absf(hits[0].first_time-0.60) < 0.02 and absf(hits[1].first_time-0.92) < 0.02 and absf(hits[2].first_time-1.24) < 0.02, "Wind pressure delivers three distinct fast beats")
			check(hits[0].key != hits[1].key and hits[1].key != hits[2].key and hits[0].key != hits[2].key, "Each cut has a distinct real attack segment")
			check(absf((hits[1].first_time-hits[0].first_time)-(hits[2].first_time-hits[1].first_time)) < 0.04, "Initial three-cut contact intervals have a stable rhythm")
			print("CONTACTS ", target, " ", JSON.stringify(hits))
		check(deer.state == DeerBoss.State.IDLE and deer.clash_phase.step_index == -1 and deer.attack_hitbox.attack == null, "Combo fully closes before manual idle")
	room.dummy_x.value = 1000
	room.play_action(0)
	tick(35)
	await snapshot("thrust_right_contact")
	room.play_action(1)
	tick(35)
	await snapshot("red_right_warning")
	tick(20)
	await snapshot("red_right_contact")
	room.dummy_x.value = 688
	room.play_action(2)
	tick(36)
	await snapshot("pressure_left_first")
	tick(20)
	await snapshot("pressure_left_second")
	tick(19)
	await snapshot("pressure_left_third")
	check(deer.animated_sprite.animation == &"bind_push_ING", "Fast sequence never resets to standing thrust or head-bobbing sweep")
	check(deer.clash_phase.pressure_fx.visible, "Horn-bound magical pressure is part of the actual action")
	room.dummy_x.value = 1000
	room.play_action(2)
	tick(56)
	await snapshot("pressure_right_second")
	room.dummy_x.value = 688
	room.play_action(2)
	tick(38)
	deer.enter_stagger(2.0)
	tick(180)
	check(room.dummy.contacts.size() == 1 and deer.clash_phase.step_index == -1 and deer.attack_hitbox.attack == null, "Stagger cancels pending cuts and damage immediately")
	check(not deer.clash_phase.pressure_fx.visible, "Interrupt clears pressure graphics as well as damage")
	room.play_action(2)
	tick(100)
	room.play_action(0)
	tick(140)
	check(room.dummy.contacts.size() == 1, "Replaying another action cannot retain delayed combo cuts")
	room.dummy_x.value = 300
	room.play_action(2)
	tick(240)
	check(room.dummy.contacts.is_empty(), "Far dummy is not reached by hidden oversized boxes")
	room.dummy_x.value = 688
	room.play_action(0)
	room.dummy_x.value = 1000
	tick(140)
	check(deer.direction < 0 and room.dummy.contacts.is_empty(), "Moving dummy after startup cannot reverse a locked attack")
	for speed_index in [0,1]:
		room.dummy_x.value = 688
		room.set_playback_speed(speed_index)
		room.play_action(2)
		tick(1200 if speed_index == 0 else 600)
		check(room.dummy.contacts.size() == 3 and deer.state == DeerBoss.State.IDLE, "Slow playback preserves three contacts and complete recovery")
		if room.dummy.contacts.size() == 3:
			check(absf(room.dummy.contacts[0].first_time - 0.60) < 0.02, "Slow playback keeps the same action-time first contact")
	room.set_playback_speed(2)
	room.play_action(2)
	tick(35)
	room.reset_room()
	await process_frame
	await process_frame
	check(room.adapter.deer.phase == 3 and room.adapter.deer.state == DeerBoss.State.IDLE and room.dummy.contacts.is_empty(), "Reset rebuilds a clean wind specimen and preserves phase selection")
	check(room.player.combat_stats.health == health_before, "BOSS-only preview leaves the observer player unharmed")
	check(FileAccess.file_exists(save_path) == had_save and (not had_save or FileAccess.get_file_as_bytes(save_path) == save_before), "Preview leaves saved progress byte-for-byte unchanged")
	current_scene = null
	room.free()
	print("CLASH: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
