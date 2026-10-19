extends SceneTree

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func run() -> void:
	(get_root().get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var room := load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate() as Chapter1DeerBossRoom
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var boss := room.deer
	boss.set_physics_process(false)
	boss.manual_control = true
	var roots := boss.root_phase
	var deaths := [0]
	room.player.combat_stats.health_depleted.connect(func() -> void: deaths[0] += 1)
	for profile in ["tracking", "heavy", "final"]:
		room.player.reset_after_map_fall(Vector2(600, 555))
		room.player.combat_stats.health = 1
		boss.phase = 2
		boss._change_state(DeerBoss.State.LIGHT)
		# The same tick would open the next hoof contact without the death guard.
		boss._time = 0.4
		var nodule := roots.add_nodule(Vector2(1100, 555))
		nodule._register_support()
		var volley := roots._new_volley(profile, 20)
		volley.preview_only = false
		volley.add_root(600, 0, 0, "high1", false)
		var pending := roots._new_volley("tracking", 20)
		pending.preview_only = false
		pending.add_root(600, 0, 0, "high1", false)
		boss._physics_process(0.2)
		check(room.player.combat_stats.health == 0, profile + ": real root hit emits player death")
		check(is_instance_valid(volley) and volley.cancelled and volley.is_queued_for_deletion(), profile + ": executing volley is cancelled and deferred for deletion")
		check(is_instance_valid(pending) and pending.cancelled and not pending.hit_target, profile + ": other volley cannot hit after death")
		check(roots.volleys.is_empty() and roots.nodules.is_empty(), profile + ": encounter tracking is cleared synchronously")
		check(room.player.sloped_ground_surfaces.is_empty(), profile + ": root terrain support is removed")
		check(boss.attack_hitbox.attack == null, profile + ": boss cannot reopen an attack in the dying frame")
		await process_frame
		await process_frame
		boss.set_physics_process(false)
		check(not is_instance_valid(volley) and not is_instance_valid(pending), profile + ": cancelled volleys are actually freed")
		check(boss.phase == 1 and room.player.combat_stats.health == room.player.combat_stats.max_health, profile + ": deferred restart restores mist phase and player health")
		check(roots.volleys.is_empty() and roots.nodules.is_empty(), profile + ": restart leaves no old roots")
	check(deaths[0] == 3, "exactly one death signal per lethal root hit")
	var terrain := roots.add_nodule(Vector2(1100, 555))
	terrain._register_support()
	var replacement := roots._new_volley("final", 20)
	roots.final_volley = replacement
	roots._spawn_final(1.0)
	check(is_instance_valid(replacement) and replacement.cancelled and replacement.is_queued_for_deletion(), "replacing final volley immediately cancels the old one")
	roots.cancel_attacks()
	check(is_instance_valid(terrain) and terrain.support_registered, "phase cancellation preserves permanent root terrain")
	check(roots.volleys.is_empty(), "phase cancellation clears all attack tracking")
	roots.reset_all()
	roots.reset_all()
	check(roots.nodules.is_empty() and room.player.sloped_ground_surfaces.is_empty(), "repeated reset safely clears permanent terrain")
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "regression does not change the saved progress")
	room.queue_free()
	await process_frame
	await process_frame
	print("ROOT_DEATH_CLEANUP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
