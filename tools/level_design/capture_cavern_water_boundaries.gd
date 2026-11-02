extends "capture_cavern_pool_branch.gd"
## Isolated setups in the real W2 geometry, followed by ordinary physics/input.
## These samples are boundary reproductions, not continuous traversal evidence.


func run() -> void:
	use_memory_progress()
	fixed_position_resets=3
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await step(18)
	if "--w1" in OS.get_cmdline_user_args():
		fixed_position_resets=1
		player.reset_after_map_fall(Vector2(3392,3966))
		await step(3)
		check(await water_journey("W1"),"The real W1 submerged foundation passage remains traversable")
		check(level.drowned_count==0 and not player.is_in_deep_water(),"W1 returns to dry ground without drowning")
		await capture("w1_exit")
		await end_pool_test(false)
		return
	player.reset_after_map_fall(Vector2(9330,2846))
	player.facing_direction=1
	var entry_safe:=true
	var entry_seen:=false
	for i in 100:
		await step(1)
		entry_safe=entry_safe and player.position.x<=9332.2
		entry_seen=entry_seen or player.swim.is_splashing()
		if i==16: await capture("01_entry_wall")
		if i==55: await capture("02_entry_settle")
	check(entry_seen and entry_safe,"Real W2 curved entry stays outside the east rock wall")
	player.reset_after_map_fall(Vector2(9330,3040))
	player.facing_direction=-1
	await step(3)
	Input.action_press(&"ui_up")
	var exit_safe:=true
	var saw_surface:=false
	for i in 160:
		await step(1)
		exit_safe=exit_safe and player.position.x<=9332.2
		saw_surface=saw_surface or player.swim.is_surfacing()
		if i==40: await capture("03_surface_wall")
		if player.swim.is_floating(): break
	release()
	check(exit_safe and saw_surface and player.swim.is_floating(),"Real W2 surfacing reaches float without entering the wall")
	await capture("04_float_wall")
	Input.action_press(&"ui_right")
	await step(45)
	release()
	check(player.position.x<=9332.2 and player.swim.is_floating(),"Floating against the real pool wall respects body width")
	player.reset_after_map_fall(Vector2(9472,3320))
	await step(3)
	Input.action_press(&"ui_up")
	var false_surface:=false
	var safe_roof:=true
	for i in 120:
		await step(1)
		false_surface=false_surface or player.swim.is_surfacing() or player.swim.is_floating()
		safe_roof=safe_roof and player.position.y>=3257.8
	release()
	check(not false_surface and safe_roof,"The actual side-recess ceiling is solid and never becomes a free surface")
	await capture("05_covered_recess")
	await end_pool_test(false)
