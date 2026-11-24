extends "../../../../tools/level_design/verify_zhenxi_last_lamp.gd"
## Production A18 route. Combat health fixtures exercise encounter settlement.


func run() -> void:
	var save := use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var previous_difficulty := assist.difficulty
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	await step(12)
	if "--garrison-only" in OS.get_cmdline_user_args():
		await check_garrison()
	else:
		await check_route(save)
	assist.set_difficulty(previous_difficulty)
	await end_test()


func check_garrison() -> void:
	await CAVERN_PREVIEW.stage_court(level)
	var gallery: Node2D = level._hidden_gallery
	gallery._start_battle()
	var boss: BossBase = gallery.general
	var guard := gallery.get_node("GeneralStart") as Marker2D
	player.reset_after_map_fall(level.to_local(guard.global_position - Vector2(340, 0)))
	player.apply_attack_facing(1.0)
	boss.phase = 3
	gallery._start_flag_defense(boss)
	var defense: Node2D = gallery._flag_defense
	check(is_instance_valid(defense), "The production third-phase fixture opens")
	if not is_instance_valid(defense):
		return
	check(defense._standard.global_position.is_equal_approx(gallery._props._standard.global_position),
		"The damageable flag is planted at the exploration banner's position")
	await tap_key(KEY_I)
	await interact()
	check(defense._arming.supply == 8 and defense._garrison.remaining() == 4 and player.input_frozen,
		"The opening pose cannot spend supply or call a company")
	await step(102)
	check(not player.input_frozen and player.facing_direction == -1.0,
		"Lan faces the western attackers at the moment the first lesson unlocks")
	await tap_key(KEY_I)
	check(defense._arming.active_move() == defense.Arsenal.WAVING and defense._arming._direction == -1.0,
		"The first real I input drives a west-facing wave")

	var health := player.combat_stats.health
	defense._hit_flag(100)
	await step(44)
	var retry: Node2D = gallery._flag_defense
	check(is_instance_valid(retry) and retry != defense and gallery.general == boss and boss.phase == 3
		and retry._flag_health == retry.FLAG_HEALTH and player.combat_stats.health == health,
		"A fallen banner restarts the defense with the same living Lan and no new duel")
	if not is_instance_valid(retry) or retry == defense:
		return
	await step(100)
	await interact()
	check(retry._garrison.remaining() == 4, "Lessons cannot spend any of the four companies")
	# Isolate order accounting and contacts from the 90-second survival test.
	retry._assault_started = true
	retry._wave = retry.LESSON_WAVES
	for expected: int in [8, 5, 3, 1]:
		await interact()
		check(retry._garrison._troops.size() == expected, "Call deploys %d visible defenders" % expected)
		await interact()
		check(retry._garrison._troops.size() == expected,
			"Pressing E during an active company preserves the next order")
		await step(42)
		await capture("zhenxi_garrison_%d" % expected)
		if expected == 1:
			retry._garrison.advance(0.7, retry._soldiers)
			var flag_health: int = retry._flag_health
			retry._hit_flag(12)
			check(retry._flag_health == flag_health, "The old soldier covers a hit that would reach the flag")
		retry._garrison.advance(9.0, retry._soldiers)
	await interact()
	check(retry._garrison.remaining() == 0 and retry._garrison._troops.is_empty(),
		"A fifth order has no company to answer")
	await capture("zhenxi_garrison_exhausted")


func check_route(save: SaveProgressService) -> void:
	var gallery := await start_chapter_fight(save)
	if gallery == null:
		return
	var layout := gallery.get_node("ChapterLayout") as Node2D
	var retry_at: Vector2 = gallery.get_node("ArenaRetry").global_position
	var first: BossBase = gallery.general
	check(is_equal_approx(player.world_max_x - player.world_min_x, 1248.0),
		"Lan is confined to the active combat viewport")
	await capture("01_zhenxi_battle")
	Input.action_press(&"ui_left")
	await step(105)
	release()
	check(is_instance_valid(first) and not gallery.general._support_in_range(gallery.GENERAL.UPPERCUT)
		and not gallery.general._support_in_range(gallery.GENERAL.REVERSE), "Melee support is gated at long range")
	# Take the ordinary death path while active effects can exist.
	player.combat_stats.apply_health_damage(player.combat_stats.health)
	await step(8)
	check(not is_instance_valid(first) and not is_instance_valid(gallery.general), "Defeat removes the boss and its effect subtree")
	check(player.global_position.distance_to(retry_at) < 5 and player.combat_stats.health == player.combat_stats.max_health,
		"Defeat returns Lan to the nearby retry point with restored health")
	check(not save.has_completed(gallery.VICTORY), "Defeat does not grant victory")
	if not await walk_to_mark(layout, "LampInspect") or not await interact_at_lamp(gallery, false):
		return
	check(is_instance_valid(gallery.general) and gallery.general.phase == 1 and gallery.general.combat_stats.health == 1200,
		"Retry starts at full health in phase one")
	if not is_instance_valid(gallery.general): return
	var right_edge := player.world_max_x
	Input.action_press(&"ui_right")
	for i in 400:
		if i % 55 == 0: Input.action_press(&"jump")
		if i % 55 == 2: Input.action_release(&"jump")
		await step(1)
		if not is_instance_valid(gallery.general) or player.position.x >= right_edge - 1: break
	release()
	check(player.position.x <= right_edge + 1 and not save.has_completed(gallery.VICTORY),
		"Running and jumping cannot bypass the active arena")
	if not is_instance_valid(gallery.general):
		if not await walk_to_mark(layout, "LampInspect") or not await interact_at_lamp(gallery, false):
			return
	var boss: BossBase = gallery.general
	if "--full-fight" in OS.get_cmdline_user_args():
		var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
		assist.set_difficulty(BattleAssistSettingsService.Difficulty.EASY)
		await attack_general(boss, 14400, true)
		await read_story(gallery)
		check(is_instance_valid(gallery._flag_defense), "Lan defeats both dueling phases with normal attacks on Easy")
	else:
		var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
		assist.set_difficulty(BattleAssistSettingsService.Difficulty.EASY)
		# The guard post is now on the far side of the plaza. Give the real input
		# driver enough time to reach it and strike through the opening volley.
		await attack_general(boss, 1050)
		if not is_instance_valid(boss): return
		# The route fixture verifies phase settlement separately from survival.
		# Reset damage already accumulated by the deliberately simple attack driver.
		player.combat_stats.restore_health()
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		for i in 1100:
			if is_instance_valid(gallery._phase_comic): await read_story(gallery)
			await step(1)
			if not is_instance_valid(boss) or gallery.general.phase == 2: break
		check(is_instance_valid(boss) and gallery.general.phase == 2, "Empty first health bar plays the production phase handoff")
		if not is_instance_valid(boss) or gallery.general.phase != 2: return
		check(boss.combat_stats.health == 1800 and boss.combat_stats.max_health == 1800, "Phase two begins with a fresh full bar")
		await capture("02_zhenxi_phase_two")
		# Use the production Easy retry rules while the stationary health fixture
		# waits through both reinforcing companies and the flag scenario runs.
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		for i in 1800:
			if not is_instance_valid(boss) or is_instance_valid(gallery._flag_defense): break
			if is_instance_valid(gallery._phase_comic): await read_story(gallery)
			await step(1)
	if not await defend_flag(gallery, save):
		return
	await step(6)
	await leave_after_victory(gallery, save)
	var old_comic := (load("res://scenes/story/comics/zhenxi_last_lamp_comic.tscn") as PackedScene).instantiate() as WindSightingComic
	check(old_comic.panels.size() == 6, "The legacy comic still contains all six storybook panels")
	old_comic.free()


func defend_flag(gallery: Node2D, save: SaveProgressService) -> bool:
	var defense: Node2D = gallery._flag_defense
	check(is_instance_valid(defense), "The second depletion starts the flag defense")
	if not is_instance_valid(defense):
		return false
	var full_fight := "--full-fight" in OS.get_cmdline_user_args()
	if not full_fight:
		# This route uses health fixtures for the duels. Start the defense itself
		# at full health instead of carrying damage from those simulated rounds.
		player.combat_stats.restore_health()
	check(not save.has_completed(gallery.VICTORY) and gallery.general.combat_target == null,
		"General becomes friendly before victory is recorded")
	check(level.camera.limit_right - level.camera.limit_left == 1920
		and not player.are_attacks_allowed() and player.are_parries_allowed(),
		"The plaza expands half a screen and ordinary attacks are sealed")
	var bat := InputEventKey.new()
	bat.physical_keycode = KEY_J
	var cast_seen := {}
	var drawn_poses := {}
	var assault_after_lessons := false
	var waves_seen := 0
	var all_west := true
	var assault_time := 0.0
	var flag_remaining: int = defense._flag_health
	var soldiers_before_shot := 0
	var last_wave_before_shot := 0
	var victory_before_duel_end := false
	var shot_cleared := false
	var enemy_entered_from_west := false
	var enemy_braced_fire := false
	var duel_started_at_full_scale := false
	var duel_contacts := 0
	var duel_departures_complete := false
	var relief_times: Array[float] = []
	if "--summon-early" in OS.get_cmdline_user_args():
		relief_times.assign([4.0, 13.0, 23.0, 34.0])
	elif "--summon-late" in OS.get_cmdline_user_args():
		relief_times.assign([46.0, 58.0, 71.0, 84.0])
	var dispatched := 0
	var guard_line := 220.0
	var defense_ticks := ceili((defense.OPENING + defense.CHARGE_SECONDS + defense.RELEASE_SECONDS
		+ defense.ShadowDuel.DURATION + 50.0) * 60.0)
	for i in defense_ticks:
		if not is_instance_valid(defense): break
		release()
		Input.action_release(&"special_attack")
		Input.action_release(&"instant_dash")
		Input.action_release(&"heal")
		Input.action_release(&"parry")
		if bat.pressed:
			bat.pressed = false
			Input.parse_input_event(bat)
		if defense._state == defense.State.HOLD:
			if not enemy_entered_from_west and is_instance_valid(defense._enemy_commander):
				enemy_entered_from_west = defense._enemy_commander.global_position.x < defense._left
			drawn_poses[defense._general.frame] = true
			waves_seen = maxi(waves_seen, defense._wave)
			assault_time = defense._assault_age
			flag_remaining = defense._flag_health
			if defense._assault_started and defense._wave == defense.LESSON_WAVES:
				assault_after_lessons = defense._arrows.is_empty() and defense._soldiers.all(
					func(soldier: Node2D) -> bool: return soldier.health <= 0)
			var camera_center: float = level.camera.get_screen_center_position().x
			var half_screen: float = root.get_visible_rect().size.x * 0.5 / level.camera.zoom.x
			var visible_troops: Array[Node2D] = []
			for soldier in defense._soldiers:
				if soldier._arrival < 0.20:
					all_west = all_west and soldier.global_position.x < defense._flag_at.x
				if soldier.health > 0 and soldier.modulate.a > 0.45 \
						and absf(soldier.global_position.x - camera_center) < half_screen - 15.0:
					visible_troops.append(soldier)
			var cooldown: Dictionary = defense._arming.cooldown
			for action: StringName in cooldown:
				if cooldown[action] > 0.0:
					cast_seen[action] = true
			if player.combat_stats.health < 60 and player.heal.charges > 0 and i % 11 == 0:
				Input.action_press(&"heal")
			if defense._assault_started:
				if dispatched < relief_times.size() and assault_time >= relief_times[dispatched] \
						and defense._garrison.can_call():
					defense.try_call_support()
					dispatched += 1
				_drive_assault(defense, visible_troops, bat, i % 7 == 0, guard_line)
			else:
				_drive_lesson(defense, visible_troops, bat, i % 7 == 0)
		elif defense._state == defense.State.RELEASE:
			victory_before_duel_end = victory_before_duel_end or save.has_completed(gallery.VICTORY)
			enemy_braced_fire = enemy_braced_fire or defense._commander_braced
			var living: int = defense._soldiers.filter(func(soldier: Node2D) -> bool:
				return soldier.health > 0).size()
			if not is_instance_valid(defense._phoenix):
				soldiers_before_shot = maxi(soldiers_before_shot, living)
				last_wave_before_shot = defense._soldiers.filter(func(soldier: Node2D) -> bool:
					return soldier.is_final_rank and soldier.health > 0).size()
			elif soldiers_before_shot > 0 and living == 0:
				shot_cleared = true
		elif defense._state == defense.State.DUEL:
			victory_before_duel_end = victory_before_duel_end or save.has_completed(gallery.VICTORY)
			var enemy: Node2D = defense._enemy_commander
			var duel: Node2D = defense._shadow_duel
			var ally: Node2D = duel._ally
			if is_instance_valid(enemy) and is_instance_valid(ally):
				var expected_scale := Vector2(1.2, 1.2)
				duel_started_at_full_scale = duel_started_at_full_scale or (
					enemy.scale.is_equal_approx(expected_scale) and ally.scale.is_equal_approx(expected_scale))
			duel_contacts = maxi(duel_contacts, duel._next_contact)
			if is_instance_valid(duel._green_ash) and is_instance_valid(duel._red_embers):
				duel_departures_complete = duel_departures_complete or (
					duel._green_ash.done and duel._red_embers.done and not enemy.visible and not ally.visible)
		await step(1)
	bat.pressed = false
	Input.parse_input_event(bat)
	Input.action_release(&"instant_dash")
	Input.action_release(&"special_attack")
	Input.action_release(&"heal")
	Input.action_release(&"parry")
	release()
	print("Defense ended at %.2fs with %d flag health, %d deployments, %d last-wave survivors and casts %s"
		% [assault_time, flag_remaining, waves_seen, last_wave_before_shot, cast_seen.keys()])
	if not relief_times.is_empty():
		check(dispatched == relief_times.size(), "The chosen relief schedule reaches all four orders")
	check(assault_after_lessons and waves_seen == gallery.FLAG_DEFENSE.WAVES.size()
		and assault_time >= gallery.FLAG_DEFENSE.CHARGE_SECONDS - 0.02,
		"Clearing the two lesson armies starts the full 90-second assault")
	check(all_west, "Every formation advances from the west")
	check(drawn_poses.keys() == [gallery.FLAG_DEFENSE.BOW_DRAWN_FRAME],
		"The general stays on a single planted full-draw pose throughout the defense")
	check(cast_seen.size() == 3, "All three borrowed skills can be used with the real Lan inputs")
	check(last_wave_before_shot > 0 and shot_cleared and enemy_entered_from_west and enemy_braced_fire,
		"The fire phoenix clears the living ranks and the west commander stands through it")
	check(duel_started_at_full_scale and duel_contacts == 10 and not victory_before_duel_end,
		"Both enlarged shadow commanders complete ten exchanges before victory is written")
	check(duel_departures_complete, "The green ash and the red embers both finish before the flag victory")
	check(gallery.won and not is_instance_valid(gallery.general) and player.are_attacks_allowed()
		and not player.input_frozen and not is_instance_valid(player.encounter_arsenal),
		"Keeping the flag grants victory after the shadow duel and restores Lan")
	return gallery.won


func _drive_lesson(defense: Node2D, visible_troops: Array[Node2D], chop: InputEventKey, cast: bool) -> void:
	var arsenal: Node = defense._arming
	if not arsenal.active_move().is_empty():
		return
	if visible_troops.is_empty():
		var offset: float = player.global_position.x - defense._flag_at.x + 208.0
		if absf(offset) > 5.0:
			Input.action_press(&"ui_left" if offset > 0.0 else &"ui_right")
		return
	if defense._wave == 1:
		if player.facing_direction > 0.0:
			Input.action_press(&"ui_left")
		if cast and arsenal.can_cast(&"wave"):
			Input.action_press(&"special_attack")
		return
	var bow_gap := INF
	var shield_gap := INF
	for soldier in visible_troops:
		var gap := player.global_position.x - soldier.global_position.x
		if soldier.role == &"bow":
			bow_gap = gap
		else:
			shield_gap = gap
	if shield_gap < 230.0 and not is_finite(bow_gap):
		Input.action_press(&"ui_right")
		return
	if is_finite(bow_gap) and bow_gap > 360.0 and shield_gap > 179.0:
		Input.action_press(&"ui_left")
		return
	if player.facing_direction > 0.0:
		Input.action_press(&"ui_left")
	if cast and 20.0 < bow_gap and bow_gap < 360.0 and arsenal.can_cast(&"dash"):
		Input.action_press(&"instant_dash")
	elif cast and 230.0 <= shield_gap and shield_gap < 330.0 and arsenal.can_cast(&"chops"):
		chop.pressed = true
		Input.parse_input_event(chop)


func _drive_assault(defense: Node2D, visible_troops: Array[Node2D], chop: InputEventKey, cast: bool, guard_line: float) -> void:
	var arsenal: Node = defense._arming
	var lan_x := player.global_position.x
	var flag_x: float = defense._flag_at.x
	var targets_in_sweep := 0
	var light_targets := 0
	var shields := 0
	var imminent := false
	var guard_tell := false
	var trailing_enemy := -INF
	var nearest_ahead := INF
	for soldier in visible_troops:
		var x := soldier.global_position.x
		var gap := lan_x - x
		if gap < 0.0:
			trailing_enemy = maxf(trailing_enemy, x)
		else:
			nearest_ahead = minf(nearest_ahead, gap)
		if 80.0 < gap and gap < 810.0:
			targets_in_sweep += 1
			imminent = imminent or x > flag_x - 628.0
		if 160.0 < gap and gap < 400.0:
			if soldier.role == &"shield":
				shields += 1
			else:
				light_targets += 1
		if soldier.role != &"bow" and -20.0 < gap and gap < 118.0 and soldier._motion == &"attack":
			guard_tell = guard_tell or (0.20 < soldier._beat and soldier._beat < 0.32)
	var line := flag_x - guard_line
	if is_finite(trailing_enemy):
		line = maxf(line, minf(flag_x + 62.0, trailing_enemy + 155.0))
	elif nearest_ahead < 82.0:
		line = maxf(line, minf(flag_x + 35.0, lan_x + 84.0))
	if lan_x < line - 12.0:
		Input.action_press(&"ui_right")
		return
	if lan_x > line + 12.0 or player.facing_direction > 0.0:
		Input.action_press(&"ui_left")
	if guard_tell and arsenal.active_move().is_empty():
		Input.action_press(&"parry")
		return
	if not cast:
		return
	if arsenal.can_cast(&"wave") and targets_in_sweep > 0 and (imminent or targets_in_sweep >= 6):
		Input.action_press(&"special_attack")
	elif arsenal.can_cast(&"chops") and nearest_ahead > 145.0 and (
			shields + light_targets >= 3 or (shields > 0 and 210.0 < nearest_ahead and nearest_ahead < 340.0 and imminent)
			or (light_targets > 0 and nearest_ahead < 290.0)):
		chop.pressed = true
		Input.parse_input_event(chop)
	elif arsenal.can_cast(&"dash") and light_targets >= 2 and nearest_ahead > 140.0:
		Input.action_press(&"instant_dash")


func attack_general(boss: BossBase, frame_limit: int, full_fight := false) -> void:
	var starting_health := boss.combat_stats.health
	var gallery := boss.get_parent()
	var attack := InputEventKey.new()
	attack.physical_keycode = KEY_J
	var hit := false
	for i in frame_limit:
		if not is_instance_valid(boss) or boss.get("phase") == 3: break
		if is_instance_valid(gallery.get("_phase_comic")):
			await read_story(gallery)
		var distance := boss.global_position.x - player.global_position.x
		Input.action_release(&"ui_left")
		Input.action_release(&"ui_right")
		if absf(distance) > 60:
			Input.action_press(&"ui_right" if distance > 0 else &"ui_left")
		if i % 12 in [0, 2]:
			attack.pressed = i % 12 == 0
			Input.parse_input_event(attack)
		await step(1)
		if not is_instance_valid(boss): break
		hit = hit or boss.combat_stats.health < starting_health
		if hit and not full_fight: break
	attack.pressed = false
	Input.parse_input_event(attack)
	release()
	check(hit, "Lan's real normal attack can damage the general in the plaza")
