extends "../../support/harness.gd"
var room: Chapter1DeerBossRoom

func snap(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

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
		check(boss.counter_ready and not boss.poise_broken and not hud.prompt.available, "Stored E does not interrupt the BOSS or light an unavailable key")
		if phase == 1: await snap("counter_wait_opening")
		boss.opening = 1
		player.position.x = 900
		await wait_frames(2)
		check(not hud.prompt.available and player.get_ready_throw_target() == null, "Far target does not show a usable E")
		player.position.x = 1320
		player.facing_direction = 1
		await wait_frames(3)
		check(hud.prompt.available and player.get_ready_throw_target() == boss, "HUD availability matches the actual E input query")
		if phase == 1: await snap("counter_E_ready")
		var event := InputEventKey.new()
		event.keycode = KEY_E
		event.physical_keycode = KEY_E
		event.pressed = true
		Input.parse_input_event(event)
		for f in 3: await physics_frame
		event.pressed = false
		Input.parse_input_event(event)
		check(not boss.counter_ready and boss.defense_credit == 0, "Actual E consumes the charge and restores all six beads")
		for f in 70: await physics_frame
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
	room.encounter.stop()
	current_scene = null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER COUNTER BEADS")
