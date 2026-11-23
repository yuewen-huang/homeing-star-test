extends "../../../support/harness.gd"

const CITY := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const SINGLES := preload("res://scripts/bosses/opera_dancer/opera_single_moves.gd")

func run() -> void:
	var save := use_memory_progress()
	var city: SunkenCavern = CITY.instantiate()
	root.add_child(city)
	current_scene = city
	var stage = city.gate_stage
	var player := city.player
	var approach: Vector2 = city.to_local(stage.to_global(Vector2(1000, 669)))
	player.reset_after_map_fall(approach)
	for i in 5: await physics_frame
	var dancer = stage.dancer
	check(is_instance_valid(dancer), "Approaching centre stage starts the boss")
	if not is_instance_valid(dancer):
		finish("GATE THEATRE")
		return
	dancer.training = SINGLES.Move.MOON + 1
	for jump in [false, true]:
		var initial_hp := player.combat_stats.health
		var pressed := false
		var seated_frames := 0
		for tick in 600:
			await physics_frame
			if dancer.singles.move != SINGLES.Move.MOON:
				if seated_frames > 0: break
				continue
			if dancer.animated_sprite.frame == 15:
				seated_frames += 1
			if jump and not pressed and dancer.age >= SINGLES.Garden.STRIKE - 0.25:
				Input.action_press(&"jump")
				pressed = true
			if pressed and dancer.age >= SINGLES.Garden.STRIKE + SINGLES.Garden.ACTIVE:
				Input.action_release(&"jump")
		Input.action_release(&"jump")
		check(seated_frames > 250, "Moon gaze holds the seated drawing")
		check(player.combat_stats.health == (initial_hp if jump else initial_hp - 16), "Floor bloom resolves once and a normal jump clears it")
	check(not dancer.singles.garden.visible and not stage.get_node("WaterOpera/Moonlight").visible and dancer.attack_hitbox.attack == null, "Recovery clears flowers, moonlight and contact")

	root.get_node("BattleAssist").set_player_invincible(false)
	player.combat_stats.apply_health_damage(1000)
	await wait_frames(8)
	check(not is_instance_valid(stage.dancer) and player.combat_stats.health == player.combat_stats.max_health and player.global_position.distance_to(stage.get_node("WingDoor").global_position) < 3, "Defeat returns Lan to the wing door")
	player.reset_after_map_fall(approach)
	for i in 5: await physics_frame
	check(is_instance_valid(stage.dancer), "Re-entering starts a fresh fight")
	if is_instance_valid(stage.dancer):
		stage.dancer.combat_stats.apply_health_damage(1000)
		await wait_frames(8)
		check(save.has_completed(stage.VICTORY) and not is_instance_valid(stage.dancer), "Victory clears and records this encounter")
	city.queue_free()
	await wait_frames(3)
	var revisit: SunkenCavern = CITY.instantiate()
	root.add_child(revisit)
	revisit.player.reset_after_map_fall(approach)
	for i in 5: await physics_frame
	check(not is_instance_valid(revisit.gate_stage.dancer) and not revisit.gate_stage.get_node("OperaDancer").visible, "Returning after victory leaves the theatre open")
	revisit.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("GATE THEATRE")
