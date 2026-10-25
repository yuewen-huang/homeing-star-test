extends "../../support/harness.gd"
## Room bounds, player contacts and retained transformation.
var room: Node2D
var player: LanPlayer
var master: Node2D



func run() -> void:
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	player = room.get_node("Lan")
	master = room.get_node("MasterBoss")
	player.set_physics_process(false)
	master.set_process(false)
	master.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	var camera := room.get_node("BattleCamera") as Camera2D
	check(not room.get_node("BossTargetDummy").visible and master.combat_target == player, "Fight targets Lan; tuning dummy is hidden")
	check(camera.limit_left == -1280 and camera.limit_right == 1280, "Room spans two screens")
	for actor in [player, master]:
		check(actor.world_min_x == -1184 and actor.world_max_x == 1184, "Actors retain camera-safe edge margin")
		check(actor.position.y == SideviewMapLayout.GROUND_BASELINE_Y, "Actors stand on shared ground baseline")
	master.position.x = 1184
	player.position.x = -1280
	player._physics_process(0)
	check(absf(player.position.x - master.position.x) <= 1088, "Combat separation stays within one screen")
	player.position.x = 1000
	master.position.x = 0
	camera.position.x = 0
	player.ultimate_active = true
	room._process(0)
	check(camera.position.x == 0, "Camera ignores nonphysical ultimate traversal")
	player.ultimate_active = false
	room._process(0)
	check(camera.position.x == 640 and master.position.x == 0, "Player-led camera clamps without dragging master")
	check(absf(master.position.x - camera.position.x) > 640 - 96, "Master may leave player-led camera")
	player.finish_defense()
	player.cancel_uncommitted_attack_effects()
	player.attack_state = player.AttackState.NONE
	player.position = Vector2(0, 555)
	master.position = Vector2(100, 555)
	var master_health: int = master.combat_stats.health
	player.start_attack_1x(1)
	player._timeline_attack_1_effect_frame(0)
	var effect = player.active_attack_effects[0]
	effect.animated_sprite.frame = 1
	effect.update_hitbox_for_frame()
	await physics_frame
	await physics_frame
	effect._physics_process(0)
	check(master.combat_stats.health < master_health, "Lan's real attack effect hits master hurtbox")
	player.cancel_uncommitted_attack_effects()
	check(master.has_node("BossStatusHUD") and master.animated_sprite.sprite_frames.get_frame_count(&"phase_2_idle") == 24, "HUD and second-phase presentation remain available")
	for stack in range(1, master.CHARGED_POWER_MAX + 1):
		master._finish_drink()
		check(master.charged_power == stack, "Completed drink settles one charged-power stack")
	check(master.phase == 1 and master.charged_power == 4, "Four drinks retain phase one")
	master.combat_stats.apply_health_damage(master.combat_stats.health)
	check(master.phase == 2 and master.state == master.State.TRANSFORM and master.combat_stats.health == master.combat_stats.max_health, "Depleted phase-one health starts phase two with full health")
	master._on_body_animation_finished()
	check(master.state == master.State.PHASE_2_IDLE and master.animated_sprite.animation == &"phase_2_idle", "Transformation returns to second-phase idle")
	expect_save_untouched()
	finish("TUTORIAL BATTLE SPACE")
