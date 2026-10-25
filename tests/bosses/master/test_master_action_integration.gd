extends "../../support/harness.gd"
var master: MasterBoss
var lan: LanPlayer
var contacts: Array[StringName] = []
var contact_times: Array[float] = []

func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	master = room.get_node("MasterBoss")
	lan = room.get_node("Lan")
	master.set_process(false)
	lan.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	master.attack_hitbox.hit_resolved.connect(func(_target: Node, _result: CombatHitResult.Type) -> void:
		if master.attack_hitbox.attack != null:
			contacts.append(master.attack_hitbox.attack.attack_id)
			if master.phase_1_action != null: contact_times.append(master.phase_1_action.elapsed))
	await physics_frame
	check(master.action_library.actions.size() == 9 and master.action_library.data.moves.size() == 7, "Nine approved body actions and seven playable moves are imported")
	var idle_rect := MasterPhase1Art.FRAMES.get_frame_texture(&"idle", 0).get_image().get_used_rect()
	var idle_scale := MasterPhase1Art.body_scale(&"idle")
	for id: String in master.action_library.actions:
		var spec: Dictionary = master.action_library.actions[id]
		var rect := master.action_library.texture(id, 0).get_image().get_used_rect()
		var factor := float(spec.scale) * master.action_library.scale
		check(is_equal_approx(rect.size.y * factor, idle_rect.size.y * idle_scale), "Standing body matches current idle height: " + id)
		var left := (float(rect.position.x) - (spec.feet as Vector2).x) * factor
		var idle_left := (float(idle_rect.position.x) - 100.0) * idle_scale
		check(is_equal_approx(left, idle_left) and is_equal_approx(float(rect.end.y), (spec.feet as Vector2).y), "Standing body retains idle registration and floor: " + id)
	check(not master.start_phase_1_action(&"spin") and not master.start_phase_1_action(&"attack_3"), "Rejected whirlwind has no callable move")
	for id: StringName in MasterActionLibrary.MOVE_IDS:
		var timeline := master.action_library.move(id)
		check(timeline.errors.is_empty() and timeline.warnings.is_empty(), "Measured source timeline validates: " + id)
		var contacts_at := timeline.contacts()
		for i in range(1, contacts_at.size()):
			check(float(contacts_at[i]) - float(contacts_at[i - 1]) >= 0.35, "Source contact gaps remain playable")
		for direction in [-1.0, 1.0]:
			master.position = Vector2(0, 555)
			master.movement_direction = direction
			lan.reset_after_map_fall(Vector2(direction * master.ATTACK_APPROACH_DISTANCE, 555))
			lan.combat_stats.restore_health()
			await physics_frame
			contact_times.clear()
			check(master.start_phase_1_action(id), "Explicit action starts in either facing: " + id)
			var action := master.phase_1_action
			var old_key := master.get_parry_chain_key()
			var seen: Dictionary = {}
			var opened: Dictionary = {}
			var recovery_checked := false
			var ticks := 0
			while master.phase_1_action != null and ticks < 1400:
				master._process(1.0 / 120.0)
				if not action._ribbons.is_empty():
					for index: int in action._ribbons:
						var ribbon: MasterBladeTrail = action._ribbons[index]
						check_trail_once(seen, index, ribbon)
				if master.attack_hitbox.attack != null:
					opened[master.attack_hitbox.attack.attack_id] = true
				if action.elapsed >= action.timeline.cancel_at and not recovery_checked:
					recovery_checked = true
					check(master.attack_hitbox.attack == null, "Final recovery and lingering trails do not deal damage")
				ticks += 1
			check(ticks < 1400 and opened.size() == timeline.cuts.size(), "All authored swings play and terminate: " + id)
			for i in range(1, contact_times.size()):
				check(contact_times[i] - contact_times[i - 1] >= 0.35, "Actual blade contacts retain the minimum parry gap")
			check(contact_times.size() == timeline.cuts.size(), "Every scaled blade reaches the target at production approach distance: " + id)
			check(master.attack_collision_shape.shape is RectangleShape2D and master.attack_hitbox.attack == null, "Move restores phase-two collision shape and clears damage")
			check(not master.pending_drink and master.charged_power == 0, "Finishing actions never schedules a drink")
			check(master.start_phase_1_action(id) and master.get_parry_chain_key() != old_key, "Replay has a new parry-assistance group")
			master._interrupt_for_special(0)
			check(master.phase_1_action == null and master.attack_hitbox.attack == null, "Real special-hit interruption cancels body, collision and effects")
			await process_frame
	check(not contacts.is_empty(), "Live current-blade queries settle real hits against Lan")
	print("Actual contacts: ", contacts.size())
	master.position = Vector2(0, 555)
	master.movement_direction = -1
	master.start_phase_1_action(&"combo_three")
	var held := master.phase_1_action
	master.parry_pause_remaining = 0.1
	master._process(0.02)
	check(is_zero_approx(held.elapsed), "Parry hit-stop freezes the entire action clock")
	master.parry_pause_remaining = 0
	master.action_clock.extend_dodge_slow(1.0)
	master._process(0.1)
	check(is_equal_approx(held.elapsed, 0.01), "Dodge bullet time slows body, trail and lunge together")
	master.action_clock.clear()
	for id: StringName in MasterActionLibrary.MECHANISM_IDS:
		check(master.play_phase_1_mechanism(id), "Mechanism body is callable: " + id)
		check(master.phase_1_action == null and master.attack_hitbox.attack == null and not master.wind_effect.visible, "Unspecified mechanism adds no attack or blade effect")
		if id == &"dodge":
			var frames := master.animated_sprite.sprite_frames
			var seconds := 0.0
			for frame in frames.get_frame_count(&"skill_dodge"):
				seconds += frames.get_frame_duration(&"skill_dodge", frame) / frames.get_animation_speed(&"skill_dodge")
			check(frames.get_frame_count(&"skill_dodge") == 16 and is_equal_approx(seconds, 1.6), "Dodge preserves all sixteen authored 100ms frames")
			check(master.get_action_time_scale() == 1.0 and (master.get_node("Hurtbox") as Area2D).collision_layer == 2, "Dodge body animation adds neither bullet time nor hurtbox invulnerability")
			var health := master.combat_stats.health
			master.receive_hit(1, lan.global_position)
			check(master.combat_stats.health < health, "Master remains damageable while the dodge animation plays")
		master._on_body_animation_finished()
		check(master.state == MasterBoss.State.CHASE and master.animated_sprite.animation == &"idle", "Mechanism animation ends cleanly")
	master.start_phase_1_action(&"combo_five")
	master._process(0.5)
	master._enter_phase_2()
	check(master.phase_1_action == null and master.attack_collision_shape.shape is RectangleShape2D, "Phase transition clears new effects and restores phase-two geometry")
	check(not master.start_phase_1_action(&"horizontal"), "Phase two cannot enter phase-one moves")
	room.free()
	current_scene = null
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	check(dev.adapter.supports_combat_simulation(), "New-action mode offers opt-in phase-one combat AI")
	for index in 4:
		dev.play_action(index)
		check(dev.adapter.master.phase_1_action.id == MasterActionLibrary.MOVE_IDS[index], "Single-skill button uses real production action")
	for index in 6:
		dev.select_combo_library(index)
		dev.play_action(4)
		if index < 3:
			check(dev.adapter.master.phase_1_action.id == MasterActionLibrary.MOVE_IDS[index + 4], "Combo dropdown calls production combo")
		else:
			check(dev.adapter.master.state == MasterBoss.State.MECHANISM, "Mechanism dropdown is body-only")
	dev.reset_room()
	await process_frame
	check(dev.specimen.get_child_count() == 2, "Reset removes every old action, trail and ghost")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER ACTION INTEGRATION")

func check_trail_once(seen: Dictionary, index: int, ribbon: MasterBladeTrail) -> void:
	var key := "trail_%d" % index
	if seen.has(key): return
	seen[key] = true
	check(ribbon.look == &"trail" and ribbon.pose_keys.size() == 33, "Every cut uses the measured 33-key 断空轨迹")
