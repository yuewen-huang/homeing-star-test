extends "test_sunken_cavern_graybox.gd"
## Continuous input replay of the lower A4 west well, starting at the A19 bank.

var foothold: Vector2
var upper_exit: Vector2


func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/a4-single-foothold")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	foothold = level.vector(nav_points.route_2_1)
	upper_exit = level.vector(nav_points.route_2_2)
	player.reset_after_map_fall(level.marker("w60"))
	level.snap_camera()
	await step(12)

	var health := player.combat_stats.health
	var kicks: Array[float] = []
	var from_bank := await walk_plain(level.vector(nav_points.route_3_0)) \
		and await wall_jump_ascent(level.vector(nav_points.route_3_1), kicks) \
		and await approach_foothold()
	check(from_bank and kicks.has(-1.0) and kicks.has(1.0), "A19 reaches the single A4 foothold continuously")
	if not from_bank:
		await end_test()
		return

	for trial in [[3296.0, 0], [3280.0, 6], [3320.0, 12]]:
		var start_x: float = trial[0]
		var delay: int = trial[1]
		var up := await walk_plain(Vector2(start_x, foothold.y)) and await kick_to_exit(delay)
		check(up, "One right-wall kick reaches the upper exit from x=%.0f after %d frames of slide" % [start_x, delay])
		if not up:
			await end_test()
			return
		var bottom := await fall_left(level.marker("w53"))
		check(bottom, "Walking left from the exit drops directly onto the lower street")
		if not bottom or not await approach_foothold():
			await end_test()
			return

	var slipped := await jump_to_wall() and await wait_for_slip()
	check(slipped, "Keeping right without kicking lets the wall slide end on the foothold")
	if slipped:
		check(await kick_to_exit(0), "Lan can retry directly from the foothold")
	check(player.combat_stats.health == health and level.drowned_count == 0,
		"Both directions and the missed kick cost no health and never reset")
	await end_test()


func approach_foothold() -> bool:
	return await walk_plain(level.vector(nav_points.route_2_0)) and await hop(foothold)


func fall_left(target: Vector2) -> bool:
	release()
	var start_y := player.position.y
	Input.action_press(&"ui_left")
	for i in 180:
		if player.position.x <= target.x + 8.0:
			Input.action_release(&"ui_left")
		if standing() and player.position.y > start_y + 3.0:
			release()
			await step(12)
			print("First landing after leaving y=%.0f: %s" % [start_y, player.position])
			return standing() and absf(player.position.y - target.y) < 2.0
		await step(1)
	release()
	return false


func wait_for_slip() -> bool:
	for i in 100:
		if standing():
			release()
			await step(10)
			return standing() and absf(player.position.y - foothold.y) < 2.0
		await step(1)
	release()
	return false


func jump_to_wall() -> bool:
	release()
	Input.action_press(&"ui_right")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	var wall := LanPlayer.AirState.WALL_SLIDING
	for i in 55:
		if player.air_state == wall:
			break
		await step(1)
	if player.air_state != wall or player.wall_slide_normal_x != -1.0:
		print("No right-wall contact at ", player.position, " state=", player.air_state)
		release()
		return false
	return true


func kick_to_exit(delay: int) -> bool:
	if not await jump_to_wall():
		return false
	await step(delay)
	var kick_at := player.position
	Input.action_press(&"jump")
	await step(1)
	Input.action_release(&"jump")
	Input.action_release(&"ui_right")
	if player.air_state != LanPlayer.AirState.RISING or player.wall_jump_direction != -1.0:
		release()
		return false

	Input.action_press(&"ui_left")
	for i in 85:
		if player.position.x < upper_exit.x - 12.0:
			Input.action_release(&"ui_left")
		if standing():
			release()
			await step(12)
			print("Wall kick at %s, settled at %s after %d frames (frame %d)" % [kick_at, player.position, i, frames])
			return standing() and absf(player.position.y - upper_exit.y) < 2.0
		await step(1)
	release()
	return false
