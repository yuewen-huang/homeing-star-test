extends SceneTree
## Diagnoses wind-phase motion smoothness. Two passes:
##  1. Fixed-step pass (development room, 1/60 s): for every combo, logs each frame's clip,
##     frame, boss position and the world bounding box of the visible body pixels, so
##     pose jumps at segment boundaries, held frames and frame skips can be found.
##  2. Real-time pass (pass "--realtime"): runs the same combos on the real clock and logs
##     process-frame times, to find hitches when effects spawn.
## Usage: Godot --path game --script tools/diagnose_deer_wind_motion.gd -- <out dir> [--realtime]

var room
var deer: DeerBoss
var output := ""
var realtime := false
var rows: Array = []
var bbox_cache: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	realtime = args.has("--realtime")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func body_box() -> Rect2:
	var sprite := deer.animated_sprite
	var key := "%s:%d" % [sprite.animation, sprite.frame]
	if not bbox_cache.has(key):
		var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
		var image := texture.get_image()
		bbox_cache[key] = Rect2(image.get_used_rect())
	var local: Rect2 = bbox_cache[key]
	var size := Vector2(256, 256)
	var origin := sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var rect := Rect2(origin + local.position, local.size)
	if sprite.flip_h: rect.position.x = -rect.end.x
	var xf := sprite.global_transform
	return Rect2(xf * rect.position, rect.size * xf.get_scale())

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.select_combo(2)
	deer = room.adapter.deer
	if not realtime:
		room.set_physics_process(false); room.player.set_physics_process(false)
		deer.set_physics_process(false); deer.vfx.set_process(false)
	var names: Array = DeerClashPhase.LIBRARY
	for index in names.size():
		room.select_combo_library(index)
		deer.position.x = 820.0
		room.play_action(4)
		var t := 0.0
		var last := Time.get_ticks_usec()
		for i in 600:
			if realtime:
				await process_frame
				var now := Time.get_ticks_usec()
				rows.append({"combo": String(names[index]), "t": t, "frame_ms": (now - last) / 1000.0, "clip": String(deer.animated_sprite.animation), "f": deer.animated_sprite.frame, "state": DeerBoss.State.keys()[deer.state]})
				t += (now - last) / 1000000.0
				last = now
			else:
				deer._physics_process(1.0 / 60.0); room._physics_process(1.0 / 60.0); deer.vfx._process(1.0 / 60.0)
				await process_frame
				var box := body_box()
				rows.append({"combo": String(names[index]), "t": t, "clip": String(deer.animated_sprite.animation), "f": deer.animated_sprite.frame,
					"x": deer.position.x, "dir": deer.direction, "box": [box.position.x, box.position.y, box.size.x, box.size.y],
					"step": deer.clash_phase.step_index, "state": DeerBoss.State.keys()[deer.state], "warn": String(deer.warning_kind)})
				t += 1.0 / 60.0
			if t > 0.5 and deer.state in [DeerBoss.State.IDLE, DeerBoss.State.WALK]: break
	var file := FileAccess.open(output.path_join("motion_realtime.json" if realtime else "motion.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows))
	file.close()
	print("DIAGNOSED %d rows" % rows.size())
	quit(0)
