extends SceneTree
## Dumps Lan's guard poses (parry, parry_success, red_parry_success frames) on a plain
## background with a 2px grid around the origin, to find where the blade meets an attack.
## Usage: --script tools/capture_lan_guard_pose.gd -- <out dir>

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var player := load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = -1000.0; player.world_max_x = 2000.0
	root.add_child(player)
	player.set_physics_process(false); player.set_process(false)
	await process_frame
	var sprite := player.animated_sprite
	var lines: Array[String] = []
	for anim in [&"parry", &"parry_success", &"red_parry_success"]:
		if anim == &"red_parry_success": sprite.offset = Vector2(LanPlayer.RED_PARRY_SPRITE_OFFSET_X, 0)
		else: sprite.offset = Vector2.ZERO
		var count := sprite.sprite_frames.get_frame_count(anim)
		for f in count:
			var tex := sprite.sprite_frames.get_frame_texture(anim, f)
			var img := tex.get_image()
			# Opaque bounds relative to the player origin.
			var used := img.get_used_rect()
			var size := Vector2(img.get_size())
			var top_left := sprite.position + sprite.offset - size * 0.5 if sprite.centered else sprite.position + sprite.offset
			lines.append("%s F%d size %s used %s -> x %.0f..%.0f y %.0f..%.0f" % [anim, f, img.get_size(), used, top_left.x + used.position.x, top_left.x + used.end.x, top_left.y + used.position.y, top_left.y + used.end.y])
			img.save_png(out.path_join("%s_%d.png" % [anim, f]))
	lines.append("sprite position %s centered %s scale %s" % [sprite.position, sprite.centered, sprite.scale])
	print("\n".join(lines))
	quit(0)
