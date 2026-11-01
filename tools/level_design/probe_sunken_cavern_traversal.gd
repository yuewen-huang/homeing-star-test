extends "../../tests/levels/chapter_2_underwater/cavern/test_sunken_cavern_graybox.gd"
## Isolated reproduction only; does not replace the continuous whole-map tour.
func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	nav_points = level.layout.navigation.points
	nav_links = level.layout.navigation.links
	nav_at = OS.get_environment("CAVERN_PROBE_FROM")
	if nav_at.is_empty(): nav_at = "w28"
	var goal := OS.get_environment("CAVERN_PROBE_TO")
	if goal.is_empty(): goal = "w36"
	player.reset_after_map_fall(level.marker(nav_at))
	await step(25)
	await capture("probe_start")
	await navigate(goal)
	await capture("probe_end")
	await end_test()
