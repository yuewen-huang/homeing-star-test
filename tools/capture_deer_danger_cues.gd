extends SceneTree
## Captures every frame of the deer's red / gold danger flash in each phase and form,
## cropped around the chest light, to check the cue is on the chest and reads clearly
## without being oversized. Usage: --script tools/capture_deer_danger_cues.gd -- <out dir>

var room
var deer: DeerBoss
var output := ""
var log_lines: Array[String] = []

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func tick(count := 1) -> void:
	for i in count:
		deer._physics_process(1.0 / 60.0)
		room._physics_process(1.0 / 60.0)
		deer.vfx._process(1.0 / 60.0)

func shot(name: String) -> void:
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var at := root.get_viewport().get_canvas_transform() * deer.vfx.chest()
	var crop := Rect2i(Vector2i(at) - Vector2i(180, 180), Vector2i(360, 360)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var region := image.get_region(crop)
	# Small cyan tick marks beside the chest point (not over it) for alignment checks.
	var c := Vector2i(at) - crop.position
	for d in range(14, 22):
		for p in [Vector2i(c.x + d, c.y), Vector2i(c.x - d, c.y), Vector2i(c.x, c.y + d), Vector2i(c.x, c.y - d)]:
			if Rect2i(Vector2i.ZERO, region.get_size()).has_point(p): region.set_pixelv(p, Color.CYAN)
	region.save_png(output.path_join(name + ".png"))

## Steps until `flash` shows, then captures each of its frames.
func capture(label: String, flash: Sprite2D, limit := 600) -> void:
	for i in limit:
		if flash.visible: break
		tick()
	if not flash.visible:
		log_lines.append("%s: NO FLASH" % label)
		return
	var chest := deer.vfx.chest()
	log_lines.append("%s: flash at %s, chest %s, scale %.2f" % [label, flash.position, chest.snapped(Vector2(2, 2)), flash.scale.x])
	var seen := {}
	for i in 40:
		if flash.visible and not seen.has(flash.frame):
			seen[flash.frame] = true
			log_lines.append("  F%d scale %.2f alpha %.2f" % [flash.frame, flash.scale.x, flash.modulate.a])
			await shot("%s_F%d" % [label, flash.frame])
		tick()

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.set_physics_process(false); room.player.set_physics_process(false)
	for phase_index in [0, 2, 4]:
		room.select_combo(phase_index)
		deer = room.adapter.deer
		deer.set_physics_process(false); deer.vfx.set_process(false)
		match phase_index:
			0:
				room.play_action(1); await capture("mist_red_heavy", deer.vfx.red_warning)
				deer._recover(0.0); tick(30)
				room.play_action(3); await capture("mist_gold_charge", deer.vfx.gold_warning)
			2:
				deer.start_clash(&"rear_gore", room.dummy.position.x); await capture("wind_red_gore", deer.vfx.red_warning)
				deer.clash_phase.cancel(); deer._recover(0.0); tick(30)
				deer.position.x = 1200.0
				deer.start_clash(&"charge", room.dummy.position.x); await capture("wind_gold_charge", deer.vfx.gold_warning)
			4:
				room.play_action(0)
				for i in 600:
					if deer.vine_phase.step == DeerVinePhase.Step.HOVER: break
					tick()
				deer.vine_phase.start_sequence(&"curtain"); await capture("vine_red_curtain", deer.vfx.red_warning)
				for i in 300:
					if deer.vine_phase.step == DeerVinePhase.Step.HOVER: break
					tick()
				deer.vine_phase.start_sequence(&"god_finale_preview"); await capture("vine_gold_god", deer.vfx.gold_warning, 1500)
	var file := FileAccess.open(output.path_join("cues.txt"), FileAccess.WRITE)
	file.store_string("\n".join(log_lines))
	file.close()
	print("\n".join(log_lines))
	quit(0)
