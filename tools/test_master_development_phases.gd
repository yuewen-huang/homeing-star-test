extends SceneTree

var room
var failures := 0
var visual_dir := "D:/HomingStar/.artifacts/master-development"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(visual_dir.path_join(label + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(visual_dir)
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames(2)
	room.select_boss(1)
	await frames(2)
	check(room.combo_picker.item_count == 2, "Both master phases selectable")
	await frames(120)
	check(not room.adapter.master.combat_timeline.is_playing(), "Manual phase one stays idle")
	for phase in 2:
		room.select_combo(phase)
		for action in 4:
			room.play_action(action)
			var master = room.adapter.master
			check(master.phase == phase + 1, "Correct phase after clean action restart")
			await frames(25)
			await capture("phase_%d_action_%d_warning" % [phase + 1, action + 1])
			await frames(30)
			await capture("phase_%d_action_%d_active" % [phase + 1, action + 1])
			await frames(220)
			check(master.attack_hitbox.attack == null, "Action releases its production hitbox")
			await capture("phase_%d_action_%d_recovery" % [phase + 1, action + 1])
		for option in room.adapter.combo_library_names().size():
			room.select_combo_library(option)
			room.play_action(4)
			await frames(400)
			check(room.adapter.master.attack_hitbox.attack == null, "Library move completes")
	room.dummy_x.value = 1000
	room.play_action(0)
	check(room.adapter.master.movement_direction > 0, "Right-side dummy sets facing")
	check(room.adapter.master.combat_target != room.player, "Observer is not the attack target")
	await frames(180)
	check(not room.dummy.contacts.is_empty(), "Phase-two real hitbox reaches right-side dummy")
	room.select_combo_library(2)
	room.play_action(4)
	await frames(55)
	room.reset_room()
	await frames(2)
	check(room.adapter.master.phase == 2, "Reset preserves selected phase")
	check(room.specimen.get_child_count() == 2, "Reset clears waves and old specimens")
	room.select_boss(0)
	await frames(2)
	check(get_nodes_in_group(&"damageable").is_empty(), "Switch leaves no attackable specimens")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists, "Preview preserves save existence")
	if exists: check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == before, "Finale preview never writes progression")
	room.queue_free()
	await frames(2)
	print("Master development failures: ", failures)
	quit(1 if failures else 0)
