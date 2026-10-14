extends SceneTree

var room
var core: RegionalCoreBoss
var failures := 0
var checks := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func advance(seconds: float, speed := 1.0) -> void:
	for tick in ceili(seconds * 60.0 / speed):
		core._physics_process(speed / 60.0)
		room._physics_process(speed / 60.0)

func select(index: int) -> void:
	room.select_boss(4 + index)
	core = room.adapter.boss as RegionalCoreBoss
	core.set_physics_process(false)
	check(core != null and core.region == index and core.manual_control, "Correct independent regional specimen %d" % index)
	check(core.get_node("Hurtbox").collision_layer == 0 and not core.is_in_group(&"damageable"), "Regional specimen cannot be attacked by preview player")
	await process_frame

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	room._process(0)
	room.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Godot capture " + label)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.player.set_physics_process(false)
	check(room.boss_picker.item_count == 8, "Four regional cores appended to existing four bosses")
	var original_ground: Array = room.player.ground_surfaces.duplicate()
	var original_blockers: Array = room.player.solid_blockers.duplicate()
	for region in 4:
		await select(region)
		var sprite := core.animated_sprite
		check(sprite.sprite_frames.get_frame_texture(&"default", 0) == RegionalCoreBoss.TEXTURES[region], "Preserves region's exact source artwork")
		check(sprite.scale.is_equal_approx(Vector2.ONE * RegionalCoreBoss.ART_SCALE) and is_equal_approx(core.position.y + sprite.position.y + 275 * sprite.scale.y, 555), "Authored uniform scale and ground anchor preserved")
		advance(8)
		check(core.action_index == -1 and core.attack_hitbox.attack == null, "No autonomous regional attacks")
		for index in 2:
			for speed in [1.0, 0.5, 0.25]:
				room.set_playback_speed([0.25, 0.5, 1.0].find(speed))
				check(is_equal_approx(Engine.time_scale, speed), "Room selects requested engine playback speed")
				room.dummy_x.value = 688
				room.play_action(index)
				var locked := core.locked_target
				var segments_before := core.segments.duplicate(true)
				room.dummy_x.value = 900
				check(core.locked_target == locked and core.segments == segments_before, "Moving dummy after start does not retarget committed action")
				room.dummy_x.value = 688
				advance(0.3, speed)
				check(core.attack_hitbox.attack == null, "Warning stage has no damage")
				if speed == 1.0: await capture("core_%d_action_%d_warning" % [region, index])
				if index == 1 and region != RegionalCoreBoss.Region.ROOT:
					var lead: float = [0.60, 0.75, 0.90][region]
					advance(lead + 0.10 - core.action_time, speed)
					check(core.warning_sprite.visible and core.warning_sprite.frame > 0 and core.to_global(core.warning_sprite.position).y > 150, "Red warning is readable and follows action time")
					if speed == 1.0: await capture("core_%d_red_warning" % region)
				var start: float = core.segments[0].start
				advance(start - core.action_time + 0.035, speed)
				check(core.attack_hitbox.attack != null, "Real attack opens from action clock")
				if speed == 1.0: await capture("core_%d_action_%d_active" % [region, index])
				var expected := 2 if region == RegionalCoreBoss.Region.WIND and index == 0 else 1
				if region == RegionalCoreBoss.Region.ROOT and index == 1: expected = 0
				advance(float(RegionalCoreBoss.DURATIONS[region][index]) - core.action_time - 0.08, speed)
				check(core.attack_hitbox.attack == null and core.stage_label() == "收招", "Recovery closes real hitbox")
				if speed == 1.0: await capture("core_%d_action_%d_recovery" % [region, index])
				check(room.dummy.contacts.size() == expected, "Expected %d distinct hits at speed %.2f: region %d action %d" % [expected, speed, region, index])
				for contact in room.dummy.contacts:
					var damage: int = [[10, 18], [12, 20], [12, 18], [14, 16]][region][index]
					check(contact.first_time >= start and contact.first_frame == 0 and contact.damage == damage, "Static F00 has genuine sampled contact time and specified damage")
				advance(0.2, speed)
				check(core.action_index == -1 and core.attack_hitbox.attack == null, "Action returns to manual idle")
				room.play_action(index)
				check(is_zero_approx(core.action_time) and core.attack_hitbox.attack == null and core.terrain.is_empty() and room.dummy.contacts.is_empty(), "Replay cancels all damage, terrain and telemetry")
		room.set_playback_speed(2)
		# Force target outside wind reach / inside a fake mist mark after locking.
		if region in [RegionalCoreBoss.Region.WIND, RegionalCoreBoss.Region.MIST]:
			room.dummy_x.value = 688
			room.play_action(0)
			room.dummy_x.value = 32 if region == RegionalCoreBoss.Region.WIND else 878
			advance(2)
			check(room.dummy.contacts.is_empty(), "Outside wind range / mist decoy never deals damage")
		# Check target-overlapping player stays safe, including root launches.
		room.dummy_x.value = 688
		room.player.position = Vector2(688, 555)
		room.play_action(0)
		advance(1.3)
		check(room.player.combat_stats.health == 100 and not root.get_node("ParryQTE").active, "Regional attack cannot hurt observer or offer QTE")
		var action_time := core.action_time
		core._parry_pause = 0.5
		advance(0.1)
		check(is_equal_approx(core.action_time, action_time), "Combat pause freezes attack timeline")
		core.cancel_action()
		check(room.player.ground_surfaces == original_ground and room.player.solid_blockers == original_blockers, "Cancellation unregisters regional terrain")
	await select(RegionalCoreBoss.Region.ROOT)
	for edge in [32.0, 1248.0]:
		room.dummy_x.value = edge
		room.play_action(1)
		check(core.segments.size() == 1, "Fully offscreen root is omitted at arena edge")
		for segment in core.segments:
			var center: Vector2 = core.to_global(segment.center)
			check(center.x - segment.size.x * 0.5 >= 32 and center.x + segment.size.x * 0.5 <= 1248, "Root geometry stays within arena boundaries")
		advance(2.4)
		check(room.dummy.contacts.is_empty(), "Root pair preserves safe target position at arena edge")
	room.dummy_x.value = 688
	room.play_action(1)
	room.dummy_x.value = 560
	advance(1.35)
	room.dummy_x.value = 816
	advance(0.4)
	check(room.dummy.contacts.size() == 2 and room.dummy.contacts[0].key != room.dummy.contacts[1].key, "Root pair has two separately budgeted contacts")
	check(core.terrain.size() == 2 and room.player.solid_blockers.size() == original_blockers.size() + 2, "Two root pillars actually register solid obstacles")
	room.player.position = Vector2(560, 390)
	check(is_equal_approx(room.player.resolve_ground_snap_y(390), 395), "Root pillar is an actual standable ground surface")
	var life: float = core.terrain[0].remaining
	core._parry_pause = 0.5
	advance(0.1)
	check(is_equal_approx(core.terrain[0].remaining, life), "Combat pause also freezes terrain lifetime")
	core._parry_pause = 0
	advance(6)
	check(core.terrain.is_empty() and room.player.solid_blockers == original_blockers and room.player.ground_surfaces == original_ground, "Terrain expires after four action seconds without leaking player registrations")
	await capture("root_terrain_expired")
	room.play_action(1)
	advance(1.8)
	core.enter_stagger(3)
	check(core.terrain.is_empty() and room.player.solid_blockers == original_blockers and core.attack_hitbox.attack == null, "Root stagger clears both damaging and solid geometry")
	core.finish_stagger()
	room.dummy_x.value = 688
	room.play_action(1)
	advance(1.8)
	room.reset_room()
	core = room.adapter.boss as RegionalCoreBoss
	core.set_physics_process(false)
	check(core.terrain.is_empty() and room.player.solid_blockers == original_blockers and room.player.ground_surfaces == original_ground, "Reset disposes active terrain")
	room.play_action(0)
	advance(0.9)
	var old: WeakRef = weakref(core)
	await select(RegionalCoreBoss.Region.VINE)
	check(old.get_ref() == null and room.player.solid_blockers == original_blockers and room.player.ground_surfaces == original_ground, "Switch releases entire previous core and terrain")
	# Shared receiver contracts, without adding a player combat toggle to the room.
	core.set_core_invulnerable(true)
	core.receive_hit(1, Vector2(700, 555))
	check(core.combat_stats.health == 300 and core.combat_stats.poise == 120, "Puzzle immunity blocks both health and poise damage")
	core.set_core_invulnerable(false)
	core.receive_hit(1, Vector2(700, 555))
	check(core.combat_stats.health == 292 and core.combat_stats.poise == 110, "Core reuses standard received-hit damage and poise contract")
	check(core.get_hit_reaction_visual().has_meta(&"combat_hit_reaction_material") and core.get_children().any(func(n: Node) -> bool: return n is CombatImpactEffect), "Received hit uses shared painted combat feedback")
	room.play_action(0)
	advance(0.8)
	core.on_attack_parried(core.attack_hitbox.attack, room.dummy.global_position)
	check(core.combat_stats.poise == 85 and core.action_index == 0, "Ordinary parry removes 25 poise and retains action")
	room.play_action(1)
	advance(1.25)
	core.on_attack_parried(core.attack_hitbox.attack, room.dummy.global_position)
	check(core.poise_broken and core.red_parry_hold and core.attack_hitbox.attack == null and core.segments.is_empty(), "Red parry enters standard stagger and cancels the whole action")
	core._on_red_parry_finished(core)
	core._parry_pause = 0
	advance(2.1)
	check(not core.poise_broken, "Shared red-parry finish releases stagger recovery")
	core.combat_stats.restore_poise()
	room.play_action(0)
	advance(0.8)
	core.combat_stats.apply_poise_damage(120)
	check(core.poise_broken and core.attack_hitbox.attack == null and core.segments.is_empty(), "Poise break interrupts every remaining attack segment")
	core.finish_stagger()
	room.play_action(0)
	advance(0.8)
	core.interrupt_with_special()
	check(core.action_index == -1 and core.attack_hitbox.attack == null, "Special interruption closes attack")
	room.play_action(0)
	advance(0.8)
	core.combat_stats.apply_health_damage(300)
	core.set_core_invulnerable(false)
	check(core.invulnerable and core.action_index == -1 and core.attack_hitbox.attack == null, "Death cleans action; puzzle unlock cannot revive core")
	var current: Node = room
	current_scene = null
	current.free()
	await process_frame
	check(is_equal_approx(Engine.time_scale, 1.0), "Exit restores preview playback speed")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists and (not exists or saved == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)), "User save remains byte-identical")
	print("REGIONAL CORE CHECKS: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
