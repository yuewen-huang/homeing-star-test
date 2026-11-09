extends "../../support/harness.gd"
var room: Chapter1DeerBossRoom

func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func settle_parry(boss: DeerDuelBoss) -> CombatAttackData:
	var attack := CombatAttackData.new(&"heal_recharge", boss, 0, 0, 0, 0)
	boss.on_attack_parried(attack, boss.global_position)
	return attack

func press_throw() -> void:
	Input.action_press(&"interact")
	for i in 3: await physics_frame
	Input.action_release(&"interact")
	await physics_frame

func check_heal_recharge() -> void:
	room.restart_mist_phase()
	var boss := room.deer
	boss.set_physics_process(false)
	var player := room.player
	var heal := player.heal
	check(heal.charges == 2, "Fresh encounter grants two heals")
	await snap("heal_opening_two")
	var first := settle_parry(boss)
	boss._on_boss_counter_parry(boss, first, Vector2.ZERO, false)
	for i in 4: settle_parry(boss)
	check(heal.charges == 2 and boss.defense_credit == 5, "Five unique parries and a duplicate give no heal")
	player.combat_stats.apply_health_damage(10)
	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	for i in 160: await physics_frame
	boss = room.deer
	boss.set_physics_process(false)
	check(room.encounter.phase == 2 and heal.charges == 2, "Natural handoff keeps the current charges")
	settle_parry(boss)
	check(heal.charges == 3 and boss.counter_ready, "Sixth parry after handoff refills one heal and unlocks E")
	await snap("heal_recharged_three")
	for i in 6: settle_parry(boss)
	check(heal.charges == 3, "Full heal stock cannot exceed three")
	player.combat_stats.set_health_ratio(0.4)
	Input.action_press(&"heal")
	await physics_frame
	await physics_frame
	Input.action_release(&"heal")
	check(heal.charges == 2 and heal.healing, "Actual heal input spends one charge")
	for i in 120:
		if not heal.healing: break
		await physics_frame
	check(not heal.healing and player.combat_stats.health == 90, "Heal restores the existing 50 HP over time")
	for i in 5: settle_parry(boss)
	check(heal.charges == 2, "Parries at capacity did not bank a refill")
	settle_parry(boss)
	check(heal.charges == 3 and boss.counter_ready, "Parries still refill heal while E waits unused")
	check(heal.try_cast() and heal.charges == 2, "A second cast spends exactly one charge")
	for i in 5: settle_parry(boss)
	room.restart_mist_phase()
	boss = room.deer
	boss.set_physics_process(false)
	check(heal.charges == 2 and not heal.healing, "Retry starts fresh and cancels the old heal")
	settle_parry(boss)
	check(heal.charges == 2, "Retry discards the old attempt's partial refill")
	room.encounter.stop()
	for i in 6: settle_parry(boss)
	check(heal.charges == 2, "Closed attempt no longer accepts parry credit")

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene = packed
	root.add_child(room)
	current_scene = room
	await wait_frames(4)
	for phase in range(1,5):
		room.encounter._spawn_phase(phase,1420)
		room.encounter.start()
		var boss := room.deer
		boss.manual_control = false
		boss.set_physics_process(false)
		boss.invulnerable = false
		boss.opening = 0
		var player := room.player
		player.reset_after_map_fall(Vector2(1320,555))
		player.facing_direction = 1
		player.combat_stats.restore_health()
		await wait_frames(2) # Boss HUD is attached deferred by production setup.
		var hud: Node
		for child in boss.get_children():
			if child is CanvasLayer and "prompt" in child: hud = child
		await wait_frames(2)
		check(hud != null and hud.prompt.broken == 0, "Phase %d starts with six solid beads" % phase)
		check(hud.prompt.get_child_count() == 0, "Counter contains no text labels or extra keycaps")
		if phase == 1: await snap("counter_6_left")
		var last_attack: CombatAttackData
		for i in DeerDuelBoss.COUNTER_PARRIES:
			last_attack = CombatAttackData.new(StringName("counter_%d_%d" % [phase,i]),boss,0,0,0,0)
			boss.on_attack_parried(last_attack,boss.global_position)
			check(boss.defense_credit == i+1, "Phase %d parry %d immediately breaks one bead" % [phase,i+1])
			if i == 0:
				boss._on_boss_counter_parry(boss,last_attack,Vector2.ZERO,false)
				check(boss.defense_credit == 1, "One settled attack cannot count twice")
				player.combat_stats.apply_health_damage(5)
				check(boss.defense_credit == 1, "Taking damage does not restore broken beads")
				await wait_frames(2)
				if phase == 1: await snap("counter_5_left")
		boss.opening = 0
		await wait_frames(2)
		check(boss.counter_ready and not boss.poise_broken and hud.prompt.available, "Stored E is available without a recovery window")
		player.position.x = 900
		player.facing_direction = -1
		if phase == 1:
			var health_before_gold := player.combat_stats.health
			boss.start_move(1, player.position.x)
			boss.age = boss.DROP_RELEASE - .15
			boss._physics_process(1.0 / 60.0)
			await press_throw()
			check(boss.counter_ready and boss.move == &"drop" and not boss.is_throw_controlled(),
				"E during the gold tell preserves the move and the stored charge")
			check(player.get_ready_throw_target() == null, "Gold windup blocks the E prompt before a hitbox opens")
			for i in 42: boss._physics_process(1.0 / 60.0)
			check(boss.opening > 0 and boss.counter_ready and player.combat_stats.health < health_before_gold,
				"Gold leap keeps its real damage and enters recovery")
			for i in 90:
				if not player.hit_reaction_active and player.air_state == LanPlayer.AirState.GROUNDED: break
				await physics_frame
		await wait_frames(3)
		check(hud.prompt.available and player.get_ready_throw_target() == boss, "Far, behind-target E is shown by the HUD")
		if phase == 1: await snap("counter_E_ready")
		await press_throw()
		check(not boss.counter_ready and boss.defense_credit == 0, "Actual E consumes the charge and restores all six beads")
		check(boss.is_throw_controlled(), "Every deer phase enters throw control on cast")
		for f in 115: await physics_frame
		check(not boss.is_throw_controlled(), "Every deer phase leaves throw control after the effect ends")
		boss._on_boss_counter_parry(boss,last_attack,Vector2.ZERO,false)
		check(boss.defense_credit == 0, "Already counted hit cannot recharge after E")
		boss.set_counter_progress(2)
		boss.restart_duel()
		boss.set_physics_process(false)
		check(boss.defense_credit == 0 and not boss.counter_ready, "Explicit retry resets the counter")
	room.encounter._spawn_phase(1,1420)
	room.encounter.start()
	room.deer.set_counter_progress(2)
	room.deer.combat_stats.apply_health_damage(room.deer.combat_stats.health)
	for f in 160: await physics_frame
	check(room.encounter.phase == 2 and room.deer.defense_credit == 2, "Natural phase handoff keeps earned progress")
	await check_heal_recharge()
	current_scene = null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER COUNTER BEADS")
