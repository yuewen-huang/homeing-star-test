extends "../../support/harness.gd"

func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"Captured " + label)


func run() -> void:
	use_memory_progress()
	var room := Node2D.new()
	root.add_child(room)
	current_scene = room
	var camera := Camera2D.new()
	camera.position = Vector2(610, 440)
	room.add_child(camera)
	camera.make_current()
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = -1800.0
	player.world_max_x = 1800.0
	room.add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(500, 555)
	player.air_state = LanPlayer.AirState.GROUNDED
	await process_frame

	player.start_attack_1x(1.0)
	for stage in [&"attack_1x", &"", &"attack_2x"]:
		check(player.can_queue_attack_input(), "Each pre-finisher ground stage can queue J")
		player.attack_queued = true
		player.queued_attack_direction = 1.0
		var clip: StringName = player.animated_sprite.animation if stage == &"" else stage
		player.on_combat_timeline_finished(clip)
	check(player.attack_state == LanPlayer.AttackState.SPECIAL_ATTACK,
		"Fourth J enters the former I slash without the E throw form")
	check(player.timeline_attack_effect.skill_hit_context.damage == CombatTuning.LAN_SPECIAL_DAMAGE,
		"The combo finisher uses the uncharged melee damage")
	check(player.sword_wave_cooldown_remaining == 0.0 and not player.sword_wave_charging,
		"The melee finisher is independent of the sword-wave skill")
	player.end_special_attack_early()

	var speeds: Array[float] = []
	var damages: Array[int] = []
	var poise: Array[int] = []
	for duration in [0.0, 0.45, 0.9]:
		player.sword_wave_cooldown_remaining = 0.0
		Input.action_press(&"special_attack")
		player.start_sword_wave(1.0, true)
		player.update_sword_wave_charge(duration)
		check(player.sword_wave_charging and player.sword_wave_fx.projectiles.is_empty(),
			"Holding I never fires early")
		if duration == 0.9:
			player.heavy_charge_visual.advance(1.0 / 60.0, true, 1.0)
			await capture("sword_wave_full_charge")
		Input.action_release(&"special_attack")
		player.update_sword_wave_charge(0.0)
		player.animated_sprite.frame = 7
		var wave := player.sword_wave_fx.projectiles.back() as LanSwordWaveProjectile
		speeds.append(wave.velocity.x)
		damages.append(wave.context.damage)
		poise.append(wave.context.poise_damage)
		if duration == 0.9 and DisplayServer.get_name() != "headless":
			player.animated_sprite.pause()
			await capture("sword_wave_release")
			player.animated_sprite.frame = 23
			player.heavy_charge_visual.advance(0.2, false, 0.0)
			await capture("sword_wave_recovery")
		player.sword_wave_fx.cancel()
		player.finish_ground_attack()
	check(speeds[0] < speeds[1] and speeds[1] < speeds[2], "Charge increases projectile speed")
	check(damages[0] < damages[1] and damages[1] < damages[2], "Charge increases projectile damage")
	check(poise[0] < poise[1] and poise[1] < poise[2], "Charge increases poise damage")
	expect_save_untouched()
	current_scene = null
	room.free()
	finish("LAN COMBO FINISHER AND CHARGED SWORD WAVE")
