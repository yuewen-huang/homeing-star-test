extends SceneTree

class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass

var room
var progress: LocalProgress
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func capture(label: String, core: RegionalCoreBoss) -> void:
	for frame in 45: core._physics_process(1.0 / 60.0)
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	(root.get_node("CombatFeedback") as CombatFeedbackService).screen_fx.clear()
	await create_timer(0.3, true, false, true).timeout
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Godot capture " + label)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	progress = LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	check(not room.shield_row.visible, "Unrelated bosses do not show core shield controls")
	for region in 4:
		progress._config = ConfigFile.new()
		room.select_boss(4 + region)
		var core := room.adapter.boss as RegionalCoreBoss
		core.set_physics_process(false)
		check(room.shield_row.visible and room.shield_toggles[0].button_pressed and room.shield_toggles[1].button_pressed, "Preview initial shields read region's real two completion records")
		check(core.invulnerable and core.shield.get_parent() == core.animated_sprite, "Protection uses actual receiver immunity and follows breathing body")
		var config_before: String = progress._config.encode_to_text()
		for state in [[true, true], [true, false], [false, true], [false, false]]:
			room.shield_toggles[0].button_pressed = state[0]
			room.shield_toggles[1].button_pressed = state[1]
			check(core.gold_shield_active == state[0] and core.blue_shield_active == state[1] and core.invulnerable == (state[0] or state[1]), "Each debug button changes only its own layer and immunity is OR")
			var hp := core.combat_stats.health
			var poise := core.combat_stats.poise
			core.receive_hit(1, Vector2(600, 555))
			core.receive_skill_hit(SkillHitContext.new(&"lan_special_attack", 18), Vector2(600, 555))
			if state[0] or state[1]:
				check(core.combat_stats.health == hp and core.combat_stats.poise == poise, "Either remaining shield blocks normal and skill damage without draining poise")
			else:
				check(core.combat_stats.health == hp - 26 and core.combat_stats.poise == poise - 10, "Removing both layers restores shared damage contracts")
			await capture("shield_%d_%d_%d" % [region, int(state[0]), int(state[1])], core)
		check(progress._config.encode_to_text() == config_before, "Debug overrides never change completion records")
		progress.set_stele_state(RegionalCoreProtection.CONDITIONS[region][0], 2)
		room.adapter.restore_preview_shields()
		room._refresh_shield_controls()
		check(not core.gold_shield_active and core.blue_shield_active and not room.shield_toggles[0].button_pressed and room.shield_toggles[1].button_pressed, "Restore button reads independent combat completion")
		room.reset_room()
		core = room.adapter.boss as RegionalCoreBoss
		core.set_physics_process(false)
		check(not core.gold_shield_active and core.blue_shield_active, "Reset discards overrides and rebuilds from real progress")
		# Actual receiver's live production binding, independently of preview overrides.
		core.bind_shield_progress(progress)
		progress.set_stele_state(RegionalCoreProtection.CONDITIONS[region][1], 2)
		check(not core.invulnerable and not core.gold_shield_active and not core.blue_shield_active, "Live save completion removes remaining layer immediately")
		progress._config = ConfigFile.new()
		progress.progress_changed.emit()
		check(core.gold_shield_active and core.blue_shield_active, "Live reset reinstates both independent protections")
		room.play_action(1)
		for frame in 80: core._physics_process(1.0 / 60.0)
		var attack := CombatAttackData.new(&"shield_parry", core, 12, 12, 180, 0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
		var poise := core.combat_stats.poise
		core.on_attack_parried(attack, room.dummy.global_position)
		check(core.combat_stats.poise == poise and not core.poise_broken and not core.red_parry_hold, "Protected core still allows player parry feedback without bypassing its shield")
		var clock := core.shield.elapsed
		core._parry_pause = 0.5
		core._physics_process(0.1)
		check(is_equal_approx(core.shield.elapsed, clock), "Shield flow and fade follow combat pause")
		core.combat_stats.apply_health_damage(300)
		progress.progress_changed.emit()
		check(not core.shield.visible and not core.gold_shield_active and not core.blue_shield_active and core.invulnerable, "Death clears both shells; later progress changes cannot show them again")
		var previous: WeakRef = weakref(core.shield)
		room.select_boss(0)
		await process_frame
		check(previous.get_ref() == null and not room.shield_row.visible, "Switching specimen releases shield and hides controls")
	var finished: Node = room
	current_scene = null
	finished.free()
	await process_frame
	progress.free()
	root.add_child(original)
	await process_frame
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == existed and (not existed or saved == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)), "User save remains byte-identical")
	print("CORE SHIELD CHECKS: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
