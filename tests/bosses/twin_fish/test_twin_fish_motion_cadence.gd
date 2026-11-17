extends SceneTree
## Measure the actual development-room fish at a 60 Hz action clock.
## CPU samples cover advance_action, not rendered frame/GPU time.
const STEP := 1.0 / 60.0
var room
var twin: TwinFishBoss
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func run() -> void:
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.boss_picker.item_selected.emit(2)
	await process_frame
	room.player.set_physics_process(false)
	twin = room.adapter.boss as TwinFishBoss
	twin.set_physics_process(false)
	print("CADENCE environment: Godot=%s display=%s renderer=%s dt=1/60 seed=41019; CPU excludes scene rendering" % [Engine.get_version_info().string, DisplayServer.get_name(), ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	measure("cold")
	measure("warm")
	room.free()
	current_scene = null
	await process_frame
	var unchanged := FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved)
	check(unchanged, "save preserved")
	print("TWIN FISH CADENCE: %d failures" % failures)
	quit(1 if failures else 0)

func blank_stats() -> Dictionary:
	return {"samples": 0, "changes": 0, "key": "", "hold": 0.0, "max_hold": 0.0, "max_hold_at": 0.0, "max_hold_frame": "", "max_step": 0.0, "max_root_speed": 0.0, "finite_root": true}

func finish_hold(stats: Dictionary, at: float) -> void:
	if stats.hold > stats.max_hold:
		stats.max_hold = stats.hold
		stats.max_hold_at = at - stats.hold
		stats.max_hold_frame = stats.key

func measure(label: String) -> void:
	twin._swim_random.seed = 41019
	twin.start_arrival()
	var metrics := {}
	var cpu := PackedFloat64Array()
	var elapsed := 0.0
	var swimmers := [twin.white_swimmer, twin.black_swimmer]
	for sample in ceili((TwinFishBoss.ARRIVAL_TIME + 24.0) / STEP):
		var previous := [swimmers[0].position - swimmers[0].root_registration, swimmers[1].position - swimmers[1].root_registration]
		var start := Time.get_ticks_usec()
		twin.advance_action(STEP)
		cpu.append(float(Time.get_ticks_usec() - start))
		elapsed += STEP
		var stage := "entry" if elapsed < TwinFishBoss.GLIDE_TIME else ("curl" if elapsed < TwinFishBoss.FREE_SWIM_TIME else "free")
		for i in 2:
			var name := stage + ("_white" if i == 0 else "_black")
			if not metrics.has(name): metrics[name] = blank_stats()
			var stats: Dictionary = metrics[name]
			var key := "%s/%d/%s" % [swimmers[i].action_name, swimmers[i].frame_index, swimmers[i].mirrored]
			stats.samples += 1
			if key != stats.key:
				finish_hold(stats, elapsed - STEP)
				stats.changes += 1
				stats.key = key
				stats.hold = STEP
			else: stats.hold += STEP
			finish_hold(stats, elapsed)
			var moved: Vector2 = swimmers[i].position - swimmers[i].root_registration - previous[i]
			stats.max_step = maxf(stats.max_step, moved.length())
			stats.max_root_speed = maxf(stats.max_root_speed, moved.length() / STEP)
			stats.finite_root = stats.finite_root and is_finite(swimmers[i].position.x) and is_finite(swimmers[i].position.y) and is_finite(swimmers[i].root_registration.x) and is_finite(swimmers[i].root_registration.y)
			# Subtract the one-time source-clip registration from physical travel.
			# The controller moves a stable canvas root. The head may independently
			# travel around that root inside the authored drawing, so it must not
			# be forced to face the root's displacement on every painted frame.
	for name in metrics:
		var stats: Dictionary = metrics[name]
		print("CADENCE %s %s %s" % [label, name, JSON.stringify(stats)])
		# Angular timing can hold a drawing for 0.125 s; allow one 60 Hz sample
		# of quantization while still rejecting the former long frozen poses.
		var limit := 0.18 if str(name).begins_with("free") else (0.145 if str(name).begins_with("curl") else 0.125)
		check(stats.max_hold <= limit, "%s %s source drawing hold %.3fs stays below %.3fs" % [label, name, stats.max_hold, limit])
		var speed_limit := 600.0 if str(name).begins_with("entry") else 240.0
		check(stats.finite_root and stats.max_root_speed <= speed_limit, "%s %s action root remains continuous with speed %.2f below %.2f px/s" % [label, name, stats.max_root_speed, speed_limit])
	cpu.sort()
	print("CADENCE %s advance_action_us n=%d p50=%.1f p95=%.1f max=%.1f" % [label, cpu.size(), cpu[floori(cpu.size()*0.50)], cpu[floori(cpu.size()*0.95)], cpu[-1]])
