extends SceneTree
## Scale matrix capture: yang_idle and yin_idle at every scale preset, frame 0, beside the Lan
## height reference. Writes a whole-room shot plus a native-pixel crop around panda and Lan.
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
	var crop := Rect2i(Vector2i(room.BOSS_START) + Vector2i(-420, -430), Vector2i(640, 470))
	for id in [&"yang_idle", &"yin_idle"]:
		for i in PandaActions.SCALE_PRESETS.size():
			room.adapter.panel.select_scale(i)
			boss.play_action(id)
			boss.tick(0.5 / float(PandaActions.spec(id).fps))
			room.adapter.panel._refresh()
			var base := "%s_scale_%s" % [id, String.num(PandaActions.SCALE_PRESETS[i], 2)]
			await shot(base + "_room")
			await shot(base + "_crop", crop)
	room.adapter.panel.select_scale(2)
	room.adapter.panel.handle_key(KEY_G)
	boss.play_action(&"yang_idle")
	boss.tick(0.5 / 12.0)
	await shot("yang_idle_scale_1.0_reference_hidden_room")
	print("Captured panda scale matrix")
	quit()