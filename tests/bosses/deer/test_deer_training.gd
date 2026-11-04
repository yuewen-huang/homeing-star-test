extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerTrainingBoss
var player: LanPlayer
var selected := -1
var output := ""
var parries := 0
var hits := 0

func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_training_adapter.gd"): selected = i
	check(selected >= 0, "Rebuild slice registered separately from production deer")
	room.select_boss(selected)
	await process_frame
	deer = room.adapter.boss
	player = room.player
	room.set_physics_process(false)
	deer.set_physics_process(false)
	player.set_physics_process(false)
	check(not room.combat_simulation and deer.manual_control, "Slice defaults to safe manual preview")
	check(room.combat_toggle.is_visible_in_tree(), "Four-button slice exposes real combat toggle")
	for index in 4:
		room.adapter.play_action(index)
		var before := player.combat_stats.health
		var saw := false
		for frame in 300:
			tick()
			saw = saw or not deer.attack_probes().is_empty()
		check(saw, "Manual move %d provides real attack probes" % index)
		check(player.combat_stats.health == before, "Manual move %d protects observer" % index)
	room.set_combat_simulation(true)
	deer.set_physics_process(false)
	player.set_physics_process(false)
	deer.manual_control = false
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	deer.attack_hitbox.hit_resolved.connect(func(_target, result):
		if result == CombatHitResult.Type.PARRY_SUCCESS: parries += 1
		if result in [CombatHitResult.Type.NORMAL_HIT, CombatHitResult.Type.PARRY_FAILURE]: hits += 1)
	# No defensive input: low front must really hit a standing Lan, once.
	reset_pair()
	var health := player.combat_stats.health
	deer.start_exercise(0, player.position.x)
	for frame in 180: tick()
	check(player.combat_stats.health == health - CombatTuning.BOSS_PLAYER_NORMAL_DAMAGE, "A hits standing Lan once through shared damage")
	# Geometric crossing: ordinary jump parabola, actual 24x58 hurtbox, both facings.
	for facing in [-1, 1]:
		reset_pair(facing)
		health = player.combat_stats.health
		deer.start_exercise(0, player.position.x)
		for frame in 160:
			var t := frame / 60.0
			var air := maxf(0, t - .65)
			player.position.y = 555 - maxf(0, 430 * air - 450 * air * air)
			tick()
		check(player.combat_stats.health == health, "A ordinary-jump geometry clears visible front facing %d" % facing)
	# Root locks once; stepping 100 pixels away clears the authored footprint.
	reset_pair()
	deer.start_exercise(1, player.position.x)
	var root_x: float = deer.root_attack._spikes[0].x
	health = player.combat_stats.health
	for frame in 170:
		if frame < 40: player.position.x -= 180.0 / 60.0
		tick()
	check(player.combat_stats.health == health, "B ordinary walking leaves its fixed root safely")
	check(is_equal_approx(root_x, 380), "B locks the original location")
	check(not is_instance_valid(deer.root_attack), "B retires without permanent terrain")
	# Combination movement route uses default walking then one ordinary jump.
	for facing in [-1, 1]:
		reset_pair(facing)
		health = player.combat_stats.health
		deer.start_exercise(3, player.position.x)
		for frame in 210:
			var t := frame / 60.0
			if t < .62: player.position.x += facing * 180.0 / 60.0
			var air := maxf(0, t - 1.10)
			player.position.y = 555 - maxf(0, 430 * air - 450 * air * air)
			tick()
		check(player.combat_stats.health == health, "B→A walking plus single jump clears both facing %d" % facing)
	# Failed B must not force A during player hit recovery.
	reset_pair()
	health = player.combat_stats.health
	deer.start_exercise(3, player.position.x)
	for frame in 180: tick()
	check(player.combat_stats.health == health - CombatTuning.BOSS_PLAYER_GOLD_DAMAGE, "Root mistake cancels uncommitted follow-up, no forced double hit")
	# Persistent body vulnerability and real production receive contract.
	reset_pair()
	deer.start_exercise(2, player.position.x)
	deer.receive_hit(1, player.position)
	check(deer.combat_stats.health < deer.combat_stats.max_health, "Body takes real damage during startup")
	reset_pair()
	deer.start_exercise(3, player.position.x)
	for frame in 35: tick()
	var held_age := deer.age
	var held_root: float = deer.root_attack._time
	deer.red_parry_hold = true
	for frame in 30: tick()
	check(is_equal_approx(deer.age, held_age) and is_equal_approx(deer.root_attack._time, held_root), "Shared red hold freezes body and root on the same clock")
	deer.red_parry_hold = false
	deer.combat_stats.apply_poise_damage(deer.combat_stats.max_poise)
	check(deer.poise_broken and deer.opening > 0 and not is_instance_valid(deer.root_attack), "Shared poise break opens counter window and cancels hazards")
	reset_pair()
	deer.start_exercise(3, player.position.x)
	deer.combat_stats.apply_health_damage(deer.combat_stats.health)
	check(deer._stopped and not is_instance_valid(deer.root_attack) and deer.attack_hitbox.attack == null, "Defeat cancels all slice hazards")
	reset_pair()
	deer.start_exercise(3, player.position.x)
	deer._on_player_defeated()
	check(deer.move == &"" and not is_instance_valid(deer.root_attack), "Practice player depletion cancels current combination")
	# Screen-space export of warning/contact/recovery, without computer use.
	if DisplayServer.get_name() != "headless":
		# Let earlier real-hit feedback expire before sampling the safe manual poses.
		for frame in 90: await process_frame
		for index in 4:
			reset_pair(1)
			deer.manual_control = true
			deer.start_exercise(index, player.position.x)
			for frame in 200:
				tick()
				if frame == 25: check(deer.move != &"" and deer.age > .40, "Native capture %d is advancing the intended move" % index)
				if frame in [25, 52, 79, 130, 175]: await capture("move_%d_%03d" % [index, frame])
	reset_pair()
	deer.start_exercise(3, player.position.x)
	var old := deer
	room.reset_room()
	await process_frame
	deer = room.adapter.boss
	deer.set_physics_process(false)
	check(deer != old and room.combat_simulation and not deer.manual_control, "R rebuilds the slice and resumes real practice")
	old = deer
	room.select_boss(0)
	await process_frame
	check(not is_instance_valid(old), "Switching specimen frees slice and effects")
	check(room.adapter.boss.get_script().resource_path.ends_with("deer_boss.gd"), "Production deer stays on original runtime")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER TRAINING SLICE")

func reset_pair(facing := -1) -> void:
	room._combat_result = ""
	player.set_input_frozen(false)
	deer.restart_slice()
	deer.set_physics_process(false)
	deer.manual_control = false
	# Suppress autonomous next action while manually advancing the chosen real move.
	deer.wait_left = 99.0
	deer.position.x = 820 if facing < 0 else 360
	player.reset_after_map_fall(Vector2(380 if facing < 0 else 800, 555))
	player.combat_stats.restore_health()
	player.set_physics_process(false)
	player.facing_direction = -facing

func tick() -> void:
	deer._physics_process(1.0 / 60.0)
	# A finished move cannot trigger another during a controlled one-shot check.
	if deer.move == &"": deer.wait_left = 99.0
	deer.vfx._process(1.0 / 60.0)

func capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
