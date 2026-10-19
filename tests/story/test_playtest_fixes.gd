extends SceneTree
## Regression checks for the pendant, stele activation and overlapping wind hazards.
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_id: StringName) -> bool: return true

var save: MemorySave
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok: failures += 1

func frames() -> void:
	await process_frame
	await physics_frame
	await process_frame

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	save._config.set_value("inventory", String(ItemCatalog.SPIRIT_PENDANT), 1)
	var inventory := root.get_node("InventoryScreen")
	inventory._save = save
	inventory._on_item_equip_requested(ItemCatalog.SPIRIT_PENDANT)
	check(save.get_equipped_special_item() == ItemCatalog.SPIRIT_PENDANT, "Owned pendant equips through inventory right-click handler")
	var drop = load("res://scripts/ui/special_item_skill_slot.gd").new()
	check(drop._can_drop_data(Vector2.ZERO, {"kind": "special_item", "item_id": String(ItemCatalog.SPIRIT_PENDANT)}), "Q slot accepts a dragged pendant")
	drop.free()
	check(not save.equip_special_item(&"unknown"), "Unowned items remain rejected")

	var mist = load("res://scenes/levels/chapter_1/chapter_1_mist_room.tscn").instantiate()
	root.add_child(mist)
	current_scene = mist
	mist.player.set_physics_process(false)
	await frames()
	check(mist.mist_enemies.is_empty() and not mist.combat_active and not mist._combat_hint.visible, "Entering mist does not start the combat puzzle")
	save.set_stele_state(mist.COMBAT_ID, MinigameStele.SteleState.UNLOCKED)
	check(mist.mist_enemies.is_empty(), "Saved unlocked stele does not auto-start combat")
	var stele := mist.get_node("CombatStele") as MinigameStele
	mist.player.position = stele.position + Vector2(-30, 0)
	await frames()
	check(stele.interact(), "Interact with unlocked combat stele")
	check(mist.combat_active and mist.mist_enemies.size() == 3 and mist._combat_hint.visible, "Stele starts exactly three mist opponents")
	stele.interact()
	check(mist.mist_enemies.size() == 3, "Repeated interaction does not duplicate opponents")
	mist._respawn()
	await frames()
	check(not mist.combat_active and mist.mist_enemies.is_empty(), "Death clears the challenge until another stele interaction")
	mist._combat_stele_requested(mist.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	for enemy in mist.mist_enemies: enemy.state = MistAmbusher.State.DEAD
	mist._on_mist_enemy_defeated(mist.mist_enemies[0])
	check(save.get_stele_state(mist.COMBAT_ID) == MinigameStele.SteleState.COMPLETED and not mist.combat_active, "Actual enemy completion still settles the stele")
	mist.free()
	current_scene = null

	save.set_stele_state(Chapter1WindRoom.PUZZLE_ID, MinigameStele.SteleState.COMPLETED)
	save.set_stele_state(Chapter1WindRoom.COMBAT_ID, MinigameStele.SteleState.UNLOCKED)
	var room := load("res://scenes/levels/chapter_1/chapter_1_wind_room.tscn").instantiate() as Chapter1WindRoom
	root.add_child(room)
	current_scene = room
	room.set_physics_process(false)
	room.camera.position_smoothing_enabled = false
	room.camera.make_current()
	room.player.set_physics_process(false)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	await frames()
	var shortcut := room._stele_shortcut
	check(shortcut.enabled, "Solved puzzle enables shortcut during exploration")
	room.player.global_position = shortcut.to_global(shortcut.route[0].lerp(shortcut.route[1], 0.5))
	shortcut._physics_process(0)
	check(room.player._wind != Vector2.ZERO, "Exploration shortcut actually queues lift")
	var platform := room.get_node("Terrain/Arena") as TerrainPiece
	room.player.reset_after_map_fall(platform.position + Vector2(440, 0))
	room._challenge(Chapter1WindRoom.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	check(room.combat_active and not shortcut.enabled and room.player._wind == Vector2.ZERO, "Combat disables shortcut and discards queued exploration lift")
	save.progress_changed.emit()
	check(not shortcut.enabled, "Progress refresh cannot re-enable shortcut during combat")
	var trial := room._combat_trial
	room._update_camera()
	room.camera.force_update_scroll()
	await capture("wind_warning")
	for flow in [WindCombatTrial.Flow.LEFT, WindCombatTrial.Flow.RIGHT, WindCombatTrial.Flow.DOWN]:
		room.player.reset_after_map_fall(platform.position + Vector2(440, 0))
		room.player.combat_stats.restore_health()
		trial.flow = flow
		trial.state = WindCombatTrial.State.WARNING
		trial.state_age = 0
		trial._advance_state()
		trial._damage_cooldown = 0
		var before := trial.hit_count
		trial.step(WindCombatTrial.SPIKE_WARNING + 0.01)
		check(trial._spike_frame() >= 0, "Spike grows during wind direction %d" % flow)
		check(room.player.horizontal_combat_wind() != 0 if flow != WindCombatTrial.Flow.DOWN else room.player.is_jump_blocked(), "Wind is active together with spikes in direction %d" % flow)
		trial.step(WindCombatTrial.SPIKE_DAMAGE_DELAY + 0.01)
		check(trial.hit_count == before + 1, "Concurrent spike actually damages the player in direction %d" % flow)
		room._update_camera()
		room.camera.reset_smoothing()
		room.camera.force_update_scroll()
		await frames()
		await capture("wind_and_spikes_%d" % flow)
	trial.state = WindCombatTrial.State.RECOVERY
	trial.state_age = 0
	trial.step(0.1)
	check(not room.player.is_jump_blocked() and room.player.combat_winds.is_empty(), "Recovery removes trial forces while shortcut remains suspended")
	await frames()
	await capture("wind_recovery")
	room.end_combat(false)
	check(shortcut.enabled and room.player.combat_winds.is_empty() and not room.player.is_jump_blocked(), "Combat exit restores shortcut and releases trial forces")
	room.free()
	current_scene = null
	print("PLAYTEST FIXES: %d failures" % failures)
	quit(1 if failures else 0)
