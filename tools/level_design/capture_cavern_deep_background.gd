extends "capture_cavern_east_crypt.gd"
## Fixed native views for a visual-only background splice, never route evidence.


func run() -> void:
	use_memory_progress()
	output=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_deep_background_20261102")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await step(18)
	for sample in [["01_entrance_preserved",Vector2(1536,2558)],["02_upper_transition",Vector2(5824,2814)],
		["03_middle_well",Vector2(5824,3582)],["04_upper_turn",Vector2(7616,4222)],
		["05_west_crypt",Vector2(4480,4990)],["06_lower_steps",Vector2(7456,5246)],
		["07_forecourt",Vector2(7712,5374)],["08_archive_preserved",Vector2(6848,1278)],
		["09_patch_join",Vector2(6592,4990)]]:
		player.reset_after_map_fall(sample[1])
		await step(18)
		await capture(sample[0])
	release()
	var report={"fixed_camera_samples":9,"position_resets":9,"continuous_real_input":false,
		"game_seconds":frames/60.0,"drowned":level.drowned_count}
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream=null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	report.checks=checks
	report.failures=failures
	var file:=FileAccess.open(output.path_join("validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	finish("CAVERN DEEP BACKGROUND")
