extends SceneTree
## Run with --path pointing at the game. All progress stays in memory.

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass

class TimedVolley extends DeerRootVolley:
	var draw_us: Array[int] = []
	func _draw() -> void:
		var started := Time.get_ticks_usec()
		super._draw()
		draw_us.append(Time.get_ticks_usec() - started)

func _initialize() -> void: call_deferred("run")

func report(label: String, samples: Array[int]) -> void:
	samples.sort()
	var total := 0
	for value in samples: total += value
	if not samples.is_empty():
		print("%s samples=%d avg_us=%d p95_us=%d max_us=%d" % [label, samples.size(), total / samples.size(), samples[int(samples.size() * 0.95)], samples.back()])

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var room := load("res://scenes/levels/chapter_1/chapter_1_root_heart_room.tscn").instantiate() as Chapter1BossRoom
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	room.regional_core.set_physics_process(false)
	var battle := room.regional_core.battle
	battle.automatic = false
	battle.preview_only = true
	battle.rng.seed = 24
	battle.spawn_nodules()
	print("NODULES=", battle.nodules.size())
	var samples: Array[int] = []
	for i in 120:
		var started := Time.get_ticks_usec()
		battle.step(1.0 / 60)
		samples.append(Time.get_ticks_usec() - started)
		await process_frame
	report("ROOT_BATTLE_STEP", samples)
	var volley := TimedVolley.new()
	volley.no_player_damage = true
	volley.ground_y = 555
	root.add_child(volley)
	for i in 3: volley.add_root(400 + i * 130, 0, 0.65, "short" + str(i + 1), i % 2 == 0)
	samples.clear()
	for i in 120:
		var started := Time.get_ticks_usec()
		volley.step(1.0 / 60)
		samples.append(Time.get_ticks_usec() - started)
		await process_frame
	report("ROOT_SPIKES_STEP", samples)
	report("ROOT_SPIKES_DRAW", volley.draw_us)
	volley.queue_free()
	battle.cancel()
	room.queue_free()
	await process_frame
	await process_frame
	var unchanged := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved
	print("SAVE_UNCHANGED=", unchanged)
	quit(0 if unchanged else 1)
