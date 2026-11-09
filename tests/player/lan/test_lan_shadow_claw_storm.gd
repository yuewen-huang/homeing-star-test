extends "../../support/harness.gd"

const FROG := preload("res://scenes/bosses/frogger/frogger_boss.tscn")
const LAN := preload("res://scenes/player/lan/lan_player.tscn")


func run() -> void:
	use_memory_progress()
	var room := Node2D.new()
	root.add_child(room)
	current_scene = room
	var floor_y := 555.0
	var camera := Camera2D.new()
	camera.position = Vector2(527.0, 463.0)
	camera.zoom = Vector2.ONE * 1.15
	room.add_child(camera)
	camera.make_current()
	var floor_art := ColorRect.new()
	floor_art.color = Color("#26393c")
	floor_art.position = Vector2(-1000.0, floor_y)
	floor_art.size = Vector2(3000.0, 500.0)
	floor_art.z_index = -8
	room.add_child(floor_art)
	RenderingServer.set_default_clear_color(Color("#19292f"))

	var player := LAN.instantiate() as LanPlayer
	player.world_min_x = 0.0
	player.world_max_x = 1600.0
	player.ground_y = floor_y
	player.position = Vector2(350.0, floor_y)
	room.add_child(player)
	player.set_physics_process(false)
	player.apply_attack_facing(1.0)
	var frog := FROG.instantiate() as FroggerBoss
	frog.combat_target = player
	frog.world_min_x = 0.0
	frog.world_max_x = 1600.0
	frog.position = Vector2(750.0, floor_y)
	room.add_child(frog)
	frog.set_physics_process(false)
	frog.combat_stats.max_health = 1200
	frog.combat_stats.restore_health()
	frog.set_counter_progress(frog.COUNTER_PARRIES)
	await process_frame
	player.get_node("SkillBar").hide()

	check(player.find_throw_target() == frog, "E finds a counter-ready boss 400 px away")
	frog.position.x = player.position.x + player.THROW_RANGE + 100.0
	player.apply_attack_facing(-1.0)
	frog.start_action(&"tongue")
	check(player.find_throw_target() == frog, "E finds an attacking boss beyond the old range and behind Lan")
	var initial_health := frog.combat_stats.health
	var cast_x := player.position.x
	var cast_animation := player.animated_sprite.animation
	Input.action_press(&"interact")
	player._physics_process(1.0 / 60.0)
	Input.action_release(&"interact")
	var storm := frog.get_node_or_null("LanShadowClawStorm")
	check(storm != null, "Real E input launches the detached effect")
	if storm == null:
		finish("LAN SHADOW CLAW STORM")
		return
	check(player.attack_state == LanPlayer.AttackState.NONE and player.animated_sprite.animation == cast_animation,
		"Cast leaves Lan's body animation and attack state alone")
	check(not frog.can_offer_break_empower() and player.find_throw_target() == null,
		"Cast consumes the existing counter opportunity once")
	check(storm.rear.z_index < frog.z_index and storm.front.z_index > frog.z_index,
		"Rear and front layers straddle the boss body")
	check(frog.combat_stats.health == initial_health, "The opening swirl is harmless before contact")
	check(frog.is_throw_controlled() and frog.action == &"hurt" and frog.attack_hitbox.attack == null,
		"Cast immediately cancels the ordinary attack and holds the boss")
	frog.set_physics_process(true)

	var folder := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var capture := not folder.is_empty() and DisplayServer.get_name() != "headless"
	Input.action_press(&"ui_left")
	var held_at := frog.position
	var stayed_held := true
	for frame in 150:
		await physics_frame
		if is_instance_valid(storm) and not storm.is_queued_for_deletion():
			stayed_held = stayed_held and frog.action_time == 0.0 and frog.position == held_at
		if frame < 32:
			player._physics_process(1.0 / 60.0)
		elif frame == 32:
			Input.action_release(&"ui_left")
			player._physics_process(1.0 / 60.0)
		if capture and frame % 2 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("claw_%03d.png" % frame))
	check(player.position.x < cast_x - 30.0, "Lan can walk away during the detached cast")
	check(frog.combat_stats.health == initial_health - player.SPECIAL_ATTACK_MAX_DAMAGE,
		"One authored contact settles the existing enhanced E damage")
	check(not is_instance_valid(storm), "Both layers clean up after playback")
	check(stayed_held and not frog.is_throw_controlled() and frog.action_time > 0.0,
		"Boss stays held until the last frame and then resumes its action clock")
	expect_save_untouched()
	current_scene = null
	room.free()
	finish("LAN SHADOW CLAW STORM")
