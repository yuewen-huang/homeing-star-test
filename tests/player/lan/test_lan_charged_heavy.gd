extends "../../support/harness.gd"

func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"Captured " + label)


func press_attack(pressed: bool) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = pressed
	Input.parse_input_event(key)


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
	player.ground_y = 555.0
	player.facing_direction = 1.0
	player.air_state = LanPlayer.AirState.GROUNDED
	await process_frame

	player.set_physics_process(true)
	for frame in 150:
		if frame % 8 == 0:
			press_attack(true)
		elif frame % 8 == 3:
			press_attack(false)
		await physics_frame
		if player.attack_state == LanPlayer.AttackState.ATTACK_3X \
				and is_instance_valid(player.timeline_attack_effect):
			break
	press_attack(false)
	player.set_physics_process(false)
	check(player.attack_state == LanPlayer.AttackState.ATTACK_3X,
		"Actual J-only input enters the ordinary ground finisher")
	var effect: Node = player.timeline_attack_effect
	check(is_instance_valid(effect) and effect.skill_hit_context == null \
			and effect.attack_hit_context.health_damage == CombatTuning.LAN_ATTACK_3X_DAMAGE,
		"The J finisher carries ordinary damage with no skill interrupt")
	check(not player.sword_wave_charging and player.sword_wave_fx.projectiles.is_empty(),
		"The melee finisher is independent of the sword-wave skill")
	player.reset_after_map_fall(Vector2(500, 555))

	var speeds: Array[float] = []
	var damages: Array[int] = []
	var poise: Array[int] = []
	for charge_ratio in [0.0, 0.5, 1.0]:
		Input.action_press(&"special_attack")
		player.start_sword_wave(1.0, true)
		player.update_sword_wave_charge(charge_ratio * LanPlayer.SWORD_WAVE_CHARGE_TIME)
		check(player.sword_wave_charging and player.sword_wave_fx.projectiles.is_empty(),
			"Holding I never fires early")
		if charge_ratio == 1.0:
			player.heavy_charge_visual.advance(1.0 / 60.0, true, 1.0)
			await capture("sword_wave_full_charge")
		Input.action_release(&"special_attack")
		player.update_sword_wave_charge(0.0)
		player.animated_sprite.frame = 7
		var wave := player.sword_wave_fx.projectiles.back() as LanSwordWaveProjectile
		speeds.append(wave.velocity.x)
		damages.append(wave.context.damage)
		poise.append(wave.context.poise_damage)
		if charge_ratio == 1.0 and DisplayServer.get_name() != "headless":
			player.animated_sprite.pause()
			await capture("sword_wave_release")
			player.animated_sprite.frame = 23
			player.heavy_charge_visual.advance(0.2, false, 0.0)
			await capture("sword_wave_recovery")
		player.sword_wave_fx.cancel()
		player.finish_ground_attack()
	check(speeds == [1105.0, 1445.0, 1785.0], "Charge interpolates between the adjusted travel speeds")
	check(damages[0] < damages[1] and damages[1] < damages[2], "Charge increases projectile damage")
	check(poise[0] < poise[1] and poise[1] < poise[2], "Charge increases poise damage")
	expect_save_untouched()
	current_scene = null
	room.free()
	finish("LAN COMBO FINISHER AND CHARGED SWORD WAVE")
