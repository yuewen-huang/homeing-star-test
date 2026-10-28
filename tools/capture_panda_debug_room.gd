extends SceneTree
## Captures the panda in the BOSS development room: the whole room once, then three frames
## (25 / 50 / 75 % of each action) as full-room shots plus a native-pixel crop around the panda.
## Usage: godot --path <game> --script <this> -- <output_dir>   (needs a real window, not --headless)

var room

func _initialize() -> void:
	call_deferred("run")

func shot(name: String, crop := Rect2i()) -> void:
	room._process(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if crop.size != Vector2i.ZERO: image = image.get_region(crop)
	image.save_png(OS.get_cmdline_user_args()[0].path_join(name + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_cmdline_user_args()[0])
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.player.set_physics_process(false)
	room.boss_picker.item_selected.emit(9)
	await process_frame
	await process_frame
	var boss := room.adapter.boss as PandaBoss
	boss.set_process(false)
	room.adapter.panel.set_process(false)
	var crop := Rect2i(Vector2i(room.BOSS_START) + Vector2i(-300, -420), Vector2i(600, 480))
	await shot("00_room_overview_yang_idle")
	var n := 0
	for action in PandaActions.ACTIONS:
		n += 1
		for step in 3:
			boss.play_action(action.id)
			var frame := int(action.frames * (step + 1) / 4.0)
			boss.tick((frame + 0.5) / float(action.fps))
			room.adapter.panel._refresh()
			var base := "%02d_%s_f%02d" % [n, action.id, boss.animated_sprite.frame]
			await shot(base + "_room")
			await shot(base + "_crop", crop)
	print("Captured panda debug room")
	quit()
