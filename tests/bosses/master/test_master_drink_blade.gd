extends "../../support/harness.gd"
## Fifth-drink ultimate: three seconds of wind and a smooth camera pull-back frame
## the blade. The master finishes the gulp, half a second passes, then the sword
## swings around the pommel gem and presses down to the floor. Six red, unguardable,
## full-arena beats sit on the press (three pressure, three edge).

var room: BossDevelopmentRoom
var master: MasterBoss
var player: LanPlayer

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))

func tick_to(time: float) -> void:
	var guard := 0
	while master.drink_blade != null and master.drink_blade.elapsed + 0.000001 < time and guard < 8000:
		master._process(minf(1.0 / 120.0, time - master.drink_blade.elapsed))
		guard += 1

func run() -> void:
	var save := use_memory_progress()
	var before := save._config.encode_to_text()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	player = room.player
	player.set_physics_process(false)
	var health := player.combat_stats.health
	check(room.adapter.has_ultimate_preview(), "Phase one exposes its own ultimate preview")
	check(room.use_preview_ultimate(), "Ultimate preview starts the fifth drink")
	master = room.adapter.master
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	check(master.drink_blade != null and master.state == MasterBoss.State.DRINK and master.charged_power == 4,
		"The fifth gulp owns the blade while at four spirit layers")
	check(master.animated_sprite.animation == &"drink", "The body keeps drinking")
	var sword := master.get_node_or_null("MasterSpiritBlade") as MasterSpiritBlade
	check(sword != null and not sword.formed, "The spirit blade gathers before it forms")

	tick_to(0.50)
	await capture("blade_gather_a")
	tick_to(1.80)
	await capture("blade_gather_b")
	check(not sword.formed and sword._threads.size() > 20, "Three seconds of filaments thicken into a vortex")
	var camera := master.get_viewport().get_camera_2d()
	check(camera != null and camera.zoom.x < 0.95, "The camera is pulling back while the blade condenses")
	check(camera.offset == Vector2.ZERO, "The camera never leaves the characters for the blade")

	tick_to(2.95)
	await capture("blade_gather_c")
	check(camera.zoom.x < 0.9, "The fight framing holds through the gather")

	tick_to(3.05)
	await capture("blade_flash")
	check(sword.formed and is_equal_approx(sword.sword.modulate.a, 1.0), "A white flash completes the painted blade")
	check(is_equal_approx(sword.sword.rotation, PI), "The blade appears vertical, tip up")
	check(assist.player_invincible, "Development preview protects the observer")

	tick_to(3.20)
	await capture("blade_idle")
	check(master.animated_sprite.animation == &"idle", "The master finishes drinking and returns to idle")
	check(master.charged_power == 5, "The gulp lands its fifth layer as the blade forms")
	check(is_equal_approx(sword.sword.rotation, PI), "No reverse wind-up before the press")

	tick_to(4.00)
	await capture("blade_press")
	check(sword.sword.rotation < PI - 0.01 and master.attack_hitbox.attack == null, "The press starts without an early hit")

	tick_to(4.12)
	await capture("blade_beat_0")
	var first := master.attack_hitbox.attack
	check(first != null and first.danger_type == CombatAttackData.DangerType.COUNTERABLE_DANGER,
		"Each beat is a red, counterable cut")
	check(not first.guardable, "The beats cannot be half-guarded")
	check(first.health_damage == CombatTuning.BOSS_PLAYER_RED_DAMAGE, "Each beat uses the red-damage budget")
	check(first.health_damage * 6 > player.combat_stats.max_health, "Eating all six kills Lan")
	check(master.drink_blade._pressures.size() == 1, "The first three beats throw air pressure")
	var pressure := master.drink_blade._pressures[0]
	check(pressure.global_position.distance_to(sword.guard_point()) < 80.0,
		"Air pressure leaves the blade itself, not the master's feet")
	var poise_before := master.combat_stats.poise
	master.on_attack_parried(first, player.global_position)
	check(master.drink_blade != null, "A parried beat does not cancel the press")
	check(master.combat_stats.poise == poise_before, "Parrying the exam does not drain the poise it runs on")
	var first_key := master.get_parry_chain_key()

	tick_to(5.00)
	var second_key := master.get_parry_chain_key()
	check(first_key != second_key, "Every beat is its own parry-chain key, so normal assist cannot chain them")
	check(master.attack_hitbox.attack != null, "The second beat opens its own hitbox")
	await capture("blade_beat_1")

	tick_to(8.15)
	await capture("blade_beat_3")
	check(master.attack_hitbox.attack != null, "The fourth beat is active on its angle")
	check(sword._edge_flash > 0.0, "The last three beats are edge contacts")
	check((master.attack_collision_shape.shape as RectangleShape2D).size.x > 1000.0, "The blade beats are judged by the blade body")

	tick_to(9.50)
	await capture("blade_ground")
	var tip_y := sword.global_position.y + cos(sword.sword.rotation) * MasterSpiritBlade.FULL_LENGTH
	check(absf(tip_y - master.global_position.y) < 20.0,
		"The edge stops when it reaches the ground (tip %.1f, ground %.1f, rot %.3f)" % [tip_y, master.global_position.y, sword.sword.rotation])

	tick_to(9.75)
	await capture("blade_dissolve")
	check(sword.dissolving, "The blade shatters in place after a half-second hold")

	tick_to(11.15)
	check(master.drink_blade == null and master.charged_power == 5, "The exam finishes with the fifth layer")
	check(master.state == MasterBoss.State.RECOVER and master.recovery_remaining > 0.0, "The exam leaves a real punish window")
	check(master._camera_rest == Vector2.ZERO and camera.offset == Vector2.ZERO, "The camera returns to its own framing")
	check(not assist.player_invincible, "The preview restores the observer's invincibility setting")
	check(player.combat_stats.health == health, "The observer never takes the exam damage")
	await process_frame
	check(master.get_node_or_null("MasterSpiritBlade") == null, "The spirit blade is freed with the preview")
	check(save._config.encode_to_text() == before, "The preview never writes progress or inventory")
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER DRINK BLADE")
