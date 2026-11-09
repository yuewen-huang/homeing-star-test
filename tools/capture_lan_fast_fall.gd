extends "level_design/capture_cavern_entrance.gd"
## Isolated height samples on the production gate floor; input/physics owns each fall.
func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/lan_fast_fall_20261104/cavern")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await step(18)
	var floor_y: float=level.marker("gate").y
	for height in [80.0,220.0,400.0]:
		release()
		Input.action_release(&"jump")
		# This column has clearance above the full 400 px drop on the gate floor.
		player.reset_after_map_fall(Vector2(2100,floor_y-height))
		player.air_state=player.AirState.FALLING
		player.play_air_animation(&"fall")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_S
		key.pressed = true
		Input.parse_input_event(key)
		await step(2)
		key.pressed = false
		Input.parse_input_event(key)
		check(player.attack_state==player.AttackState.FAST_FALL,"Production scene accepts S alone from %.0f" % height)
		for i in 120:
			await step(1)
			if player.air_state==player.AirState.GROUNDED: break
		var measured_height := player.fast_fall.last_height
		check(absf(player.position.y-floor_y)<1 and absf(measured_height-height)<2,
			"Actual gate floor determines drop height (%.2f of %.0f)" % [measured_height,height])
		await step(3)
		await capture("land_%.0f" % height)
		check(player.fast_fall.last_damage==player.fast_fall.damage(measured_height),"Production damage uses the measured drop height")
		await step(30)
	check(player.get_node("StateTrace").report_count==0,"Production drops do not contradict animation ownership")
	await end_entry_test()
