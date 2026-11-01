extends SceneTree
## Root-core runtime regression: frame parity, timed hazards, I input and cleanup.

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func check_art() -> void:
	# Compare the optimized lookup against the source resource, including both
	# sides of every authored frame boundary and the held final frame.
	var source := load(DeerRootArt.ROOT + "timelines.tres")
	var data: Dictionary = JSON.parse_string(String(source.get_meta(&"timelines")))
	for key: String in data.clips:
		var frames: Array = data.clips[key].frames
		var durations := PaintedTimeline.durations(frames)
		var parity := true
		for index in frames.size():
			var boundary := PaintedTimeline.seconds_before(durations, index)
			for seconds in [boundary - 0.000002, boundary, boundary + 0.000002, 100.0]:
				var expected := PaintedTimeline.index_at(durations, seconds, 0.000001)
				if expected < 0: expected = frames.size() - 1
				parity = parity and DeerRootArt.frame_index(key, seconds) == expected
			var atlas := DeerRootArt.atlas(key, index)
			var region: Array = frames[index].region
			parity = parity and atlas.region == Rect2(region[0], region[1], region[2], region[3])
			parity = parity and atlas.atlas == DeerRootArt.texture(key)
			parity = parity and atlas == DeerRootArt.atlas(key, index)
		check(parity, key + ": authored timing/regions preserved and atlas instances reused")

func run() -> void:
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var progress := MemoryProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	check_art()
	var room := load("res://scenes/levels/chapter_1/chapter_1_root_heart_room.tscn").instantiate() as Chapter1BossRoom
	root.add_child(room)
	current_scene = room
	var player := room.player
	var core := room.regional_core
	player.set_physics_process(false)
	core.set_physics_process(false)
	var battle := core.battle
	battle.automatic = false
	battle.preview_only = true
	battle.rng.seed = 24
	await process_frame
	battle.spawn_nodules()
	check(battle.nodules.size() in [3, 4], "Production root core spawns three or four nodules")
	var nodule := battle.nodules[0]
	for i in 30: battle.step(1.0 / 60)
	check(not nodule.supports.is_empty(), "Grown nodule registers traversable slopes")
	var held_texture := nodule.sprite.texture
	for i in 30: battle.step(1.0 / 60)
	check(nodule.sprite.texture == held_texture, "Held nodule reuses its final atlas frame")
	nodule.age = nodule.YELLOW_AT - 0.01
	nodule.step(0.02)
	check(nodule.stage == 1 and nodule.sprite.modulate == Color(1.8, 1.35, 0.3), "Four-second yellow change refreshes the held frame")
	nodule.age = nodule.RED_AT - 0.01
	nodule.step(0.02)
	check(nodule.stage == 2 and nodule.sprite.modulate == Color(1.9, 0.35, 0.28), "Eight-second red change refreshes the held frame")
	nodule.age = nodule.EXPLODE_AT - 0.01
	nodule.step(0.02)
	check(nodule.broken and nodule.supports.is_empty() and battle.hazards.size() == 1, "Timed explosion removes terrain and spawns one blast")
	battle._prune_finished()
	var destroyed := battle.nodules[0]
	for i in 5: destroyed.receive_hit(1, player.position)
	check(not destroyed.broken and destroyed.health == 8, "Tough nodule survives five normal contacts")
	destroyed.receive_hit(1, player.position)
	check(destroyed.broken and destroyed.supports.is_empty() and battle.hazards.size() == 1, "Sixth contact safely destroys nodule without another explosion")
	# Exercise the real player input path while root terrain and spikes exist.
	var volley := battle.spawn_spikes([400, 530, 660])
	check(volley.active_rects().is_empty(), "Spikes have no damage before the warning ends")
	volley.step(0.82)
	check(volley.active_rects().size() == 3, "Three painted spikes retain their active hit regions")
	Input.action_press(&"special_attack")
	player._physics_process(1.0 / 60)
	check(player.special_attack_charging, "I press begins the real skill during root hazards")
	for i in 12:
		battle.step(1.0 / 60)
		player._physics_process(1.0 / 60)
	Input.action_release(&"special_attack")
	player._physics_process(1.0 / 60)
	check(not player.special_attack_charging and player.attack_state == LanPlayer.AttackState.SPECIAL_ATTACK, "I release commits the skill during root hazards")
	player.end_special_attack_early()
	volley.step(1.0)
	check(volley.active_rects().is_empty(), "Spike damage ends after the active window")
	for i in 90: battle.step(1.0 / 60)
	check(battle.spikes.is_empty() and battle.hazards.is_empty(), "Finished volleys and explosions leave encounter tracking")
	battle.cancel()
	check(battle.nodules.is_empty() and player.sloped_ground_surfaces.is_empty(), "Cancelling the encounter clears all nodule terrain")
	await process_frame
	check(not is_instance_valid(nodule) and not is_instance_valid(volley), "Expired root nodes are freed")
	room.queue_free()
	await process_frame
	await process_frame
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "Runtime regression preserves save bytes")
	print("REGIONAL_ROOT_RUNTIME: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
