extends SceneTree
## Captures normal difficulty's blue parry cue on Lan's blade during a wind thrust: the ring
## appearing, closing, the press flash and a wide view. Placeholder art check.
## Usage: --script tools/capture_parry_cue.gd -- <out dir>

var room
var deer: DeerBoss
var lan: LanPlayer
var output := ""
var log_lines: Array[String] = []

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func tick() -> void:
	deer._physics_process(1.0 / 60.0)
	room._physics_process(1.0 / 60.0)
	deer.vfx._process(1.0 / 60.0)

func shot(name: String, half := 120) -> void:
	room._process(0)
	await physics_frame
	# The cue drops when a physics frame passes without a report; report again for the shot.
	lan.parry_cue.report(deer, deer.clash_phase.next_parry_contact_in())
	lan.parry_cue._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var at := root.get_viewport().get_canvas_transform() * lan.parry_cue.global_position
	var crop := Rect2i(Vector2i(at) - Vector2i(half, half), Vector2i(half * 2, half * 2)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.get_region(crop).save_png(output.path_join(name + ".png"))
	log_lines.append("%s: t=%.2f visible=%s at %s" % [name, lan.parry_cue.time_to_contact, lan.parry_cue.visible, lan.parry_cue.global_position.snapped(Vector2(1, 1))])

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	room.select_combo(2)
	deer = room.adapter.deer
	lan = deer.combat_target
	deer.set_physics_process(false); deer.vfx.set_process(false)
	lan.global_position.x = room.dummy.position.x
	deer.position.x = room.dummy.position.x + 175.0
	deer.start_clash(&"thrust", room.dummy.position.x)
	var targets := [[0.60, "cue_1_appear"], [0.40, "cue_2_closing"], [0.25, "cue_3_closed"], [0.12, "cue_4_flash"]]
	for target in targets:
		for i in 120:
			var t := deer.clash_phase.next_parry_contact_in()
			if t >= 0.0 and t <= float(target[0]): break
			tick()
		await shot(target[1])
	deer.clash_phase.cancel(); deer._recover(0.0)
	for i in 30: tick()
	deer.position.x = room.dummy.position.x + 175.0
	deer.start_clash(&"thrust", room.dummy.position.x)
	for i in 120:
		var t := deer.clash_phase.next_parry_contact_in()
		if t >= 0.0 and t <= 0.3: break
		tick()
	await shot("cue_5_wide", 260)
	var file := FileAccess.open(output.path_join("cue.txt"), FileAccess.WRITE)
	file.store_string("\n".join(log_lines))
	file.close()
	print("\n".join(log_lines))
	quit(0)
