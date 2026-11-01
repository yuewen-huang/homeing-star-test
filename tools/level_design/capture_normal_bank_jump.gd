extends "../../tests/support/harness.gd"
## Native review of the ordinary bank jump in the user's tower scene.


func run() -> void:
	use_memory_progress()
	var level := (load("res://scenes/levels/chapter_2_underwater/tower/underwater_tower_foundation.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	var player: LanPlayer = level.player
	player.reset_after_map_fall(Vector2(812, 3555))
	await physics_frame
	await physics_frame
	player.facing_direction = -1.0
	var start := player.position
	Input.action_press(&"jump")
	await physics_frame
	await physics_frame
	Input.action_release(&"jump")
	check(player.animated_sprite.animation == &"jump_start", "Pool-facing bank uses ordinary jump_start")
	check(player.position.y < start.y and player.animated_sprite.animation == &"jump_start", "Normal jump rises immediately, without dive anticipation")
	level.snap_camera()
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/normal_bank_jump_20261031/normal_bank_jump.png")
	check(root.get_texture().get_image().save_png(out) == OK, "Native bank jump screenshot saved")
	expect_save_untouched()
	finish("NORMAL BANK JUMP VISUAL")
