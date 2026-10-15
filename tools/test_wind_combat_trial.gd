extends SceneTree

## Real-room integration; progress stays in memory and the runner backs up saves.
class TestProgress extends SaveProgressService:
	var writes_fail := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return not writes_fail
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var room: Chapter1WindRoom
var save: TestProgress
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(filename + ".png"))

func tick(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		if room.combat_active:
			room._update_combat(1.0 / 60.0)

func start() -> WindCombatTrial:
	room.player.reset_after_map_fall(Vector2(room.arena_rect.get_center().x, room.get_node("Terrain/Arena").position.y))
	room.player.combat_stats.restore_health()
	room._challenge(Chapter1WindRoom.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	return room._combat_trial

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	room = load("res://scenes/sideview/chapter_1_wind_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames(3)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	save.set_stele_state(Chapter1WindRoom.COMBAT_ID, MinigameStele.SteleState.UNLOCKED)
	var trial := start()
	room.camera.position = room.player.position - Vector2(0, 110)
	room.camera.reset_smoothing()
	await frames()
	check(room.combat_active and trial.state == WindCombatTrial.State.WARNING, "Bird trial starts with a harmless warning")
	check(WindThornWallArt.frame_count() == 6 and is_equal_approx(WindThornWallArt.duration(), 0.6), "Supplied thorn wall retains all six original 100ms frames")
	check(trial._wall_sprites[0].scale == Vector2.ONE * 1.4 and trial._wall_sprites[1].scale == Vector2(-1.4, 1.4), "Walls keep their authored proportions at 1.4 with mirrored right side")
	check(trial._wall_sprites[0].offset == -WindThornWallArt.pivot(), "All growth frames share the root pivot instead of being separately normalized")
	check(trial._wind_visual.get_script() == WindCombatTrial.WIND_FLOW and trial._wind_material.shader.resource_path.ends_with("wind_grove_flow.gdshader"), "Trial reuses the map's existing wind flow renderer and shader")
	check(not room.combat.can_interact(), "Stele interaction hint stays hidden during the trial")
	check(room.player.horizontal_combat_wind() == 0 and not room.player.is_jump_blocked(), "Warning permits ordinary movement and jumps")
	room._challenge(Chapter1WindRoom.COMBAT_ID, 1)
	check(room._combat_trial == trial, "Repeated stele interaction does not spawn duplicate birds")
	await capture("wind_trial_warning")
	tick(0.25)
	check(trial._wall_frame() == 2 and trial._wall_sprites[0].texture == WindThornWallArt.texture(2), "Warning plays the native middle growth frame before any wind damage")
	await capture("wind_trial_wall_growth")
	tick(0.75)
	await frames()
	check(room.player.horizontal_combat_wind() < -LanPlayer.WALK_SPEED and absf(room.player.horizontal_combat_wind()) < LanPlayer.RUN_SPEED, "First wind overpowers walking but permits running against it")
	var grounded_position := room.player.position
	room.player.position.y -= 380.0
	room._update_combat(0.0)
	check(room.combat_active, "A double jump above the platform does not count as leaving the arena")
	room.player.position = grounded_position
	check(trial._walls.all(func(c: CollisionShape2D) -> bool: return not c.disabled), "Both thorn walls physically block horizontal escapes")
	await capture("wind_trial_left_active")
	var before := trial.state_age
	trial.step(0.0)
	check(trial.state_age == before, "Zero action delta freezes the trial")
	# Real player movement: idle is carried toward the wall, running reverses it.
	var x := room.player.position.x
	room.player.set_physics_process(true)
	for i in 30: await physics_frame
	room.player.set_physics_process(false)
	check(room.player.position.x < x - 70, "Wind moves an idle player through the real movement controller")
	room.player.reset_after_map_fall(Vector2(room.arena_rect.get_center().x, 730))
	Input.action_press("ui_right")
	room.player.facing_direction = 1.0
	room.player.play_run()
	x = room.player.position.x
	room.player.set_physics_process(true)
	for i in 60: await physics_frame
	room.player.set_physics_process(false)
	Input.action_release("ui_right")
	check(room.player.position.x > x + 40, "Sustained running can move away from the downwind wall")
	room.player.reset_after_map_fall(Vector2(room.arena_rect.position.x + 25, 730))
	trial._damage_cooldown = 0.0
	tick(0.02)
	check(trial.hit_count == 1, "Thorn contact counts one actual injury")
	tick(0.2)
	check(trial.hit_count == 1, "Persistent contact cannot damage every physics frame")
	room.player.combat_stats.restore_health()
	check(trial.hit_count == 1, "Healing does not erase accumulated injuries")
	room.player.reset_after_map_fall(Vector2(room.arena_rect.get_center().x, 730))
	tick(5.0)
	check(trial.flow == WindCombatTrial.Flow.RIGHT and trial.state == WindCombatTrial.State.WARNING, "Left flow gives a warning before reversing")
	check(room.player.horizontal_combat_wind() == 0, "Wind stops during direction warning")
	check(trial._wall_frame() == 5 and trial._wall_sprites[0].visible, "Grown walls hold across the left-to-right warning")
	tick(1.0)
	check(room.player.horizontal_combat_wind() > 0, "Right flow pushes in the opposite direction")
	await capture("wind_trial_right_active")
	tick(5.0)
	check(trial.flow == WindCombatTrial.Flow.DOWN and trial._wall_frame() >= 0 and trial._wall_frame() < 5, "Downwind warning retracts the same original growth frames in reverse")
	await capture("wind_trial_wall_retract")
	tick(1.0)
	await frames()
	check(trial.flow == WindCombatTrial.Flow.DOWN and trial.state == WindCombatTrial.State.ACTIVE, "Third segment enters downward flow")
	check(room.player.is_jump_blocked() and room.player.horizontal_combat_wind() == 0, "Downward flow blocks both jump inputs and clears horizontal push")
	check(trial._walls.all(func(c: CollisionShape2D) -> bool: return c.disabled), "Side walls withdraw during the ground-spike segment")
	check(trial._wall_sprites.all(func(s: Sprite2D) -> bool: return not s.visible), "Both painted walls finish retracting before ground spikes activate")
	Input.action_press("ui_accept")
	room.player.update_jump_input_buffer(1.0 / 60.0)
	check(not room.player.has_buffered_jump(), "Jump input cannot leak through the downwind blocker")
	Input.action_release("ui_accept")
	var locked_x := trial.spike_x
	room.player.position.x += 200
	tick(0.05)
	check(trial.spike_x == locked_x, "Spike warning locks its position instead of following the player")
	await capture("wind_trial_ground_warning")
	room.player.position.x = locked_x
	room.player.start_back_dodge(1.0)
	var hits := trial.hit_count
	# Enter the damaging pulse while the real dodge invulnerability is active.
	tick(maxf(0, WindCombatTrial.SPIKE_WARNING + WindCombatTrial.SPIKE_DAMAGE_DELAY - trial.spike_age) + 0.01)
	check(trial.hit_count == hits, "Dodge invulnerability avoids the ground-spike injury")
	check(trial._spike_frame() >= 0 and DeerRootArt.texture(trial._spike_key).resource_path.contains("deer_root_painted"), "Active spike uses an existing painted root frame with its authored timing")
	await capture("wind_trial_ground_active")
	room.player.reset_after_map_fall(Vector2(locked_x, 730))
	tick(0.1)
	check(trial.hit_count == hits, "Evaded pulse is consumed and cannot hit after the dodge ends")
	# Complete pulse, then stand in the next warning and active interval.
	tick(1.8)
	check(trial.hit_count == hits + 1, "Standing in the next active spike pulse receives damage")
	assist.set_player_invincible(true)
	tick(3.0)
	check(trial.state == WindCombatTrial.State.RECOVERY and not room.player.is_jump_blocked(), "Round recovery restores jumps and removes hazards")
	await capture("wind_trial_recovery")
	tick(1.2)
	check(trial.round_index == 1 and trial.active_duration() > 5.0 and trial.wind_speed() > 190.0, "Second round has greater duration and wind strength")
	tick(25.2)
	check(trial.round_index == 2 and trial.active_duration() > 7.0 and trial.wind_speed() > 220.0, "Third round increases duration and strength again")
	# Exactly two real hits pass; failed persistence offers E save retry.
	# Horizontal segments now also have spikes; isolate the saved-result boundary
	# from injuries accumulated while deliberately standing still in those pulses.
	trial.hit_count = 2
	save.writes_fail = true
	tick(32.0)
	check(not room.combat_active and room._combat_completion_pending and room.combat.state == MinigameStele.SteleState.UNLOCKED, "Passing result rolls back on failed save and retains retry")
	check(room.player.combat_winds.is_empty() and not room.player.is_jump_blocked(), "Completion clears the source's wind and jump blocker")
	save.writes_fail = false
	room._challenge(Chapter1WindRoom.COMBAT_ID, 1)
	check(room.combat.state == MinigameStele.SteleState.COMPLETED and not room.combat_active, "E retries the passed result without replaying the whole trial")
	check(room.combat.can_interact(), "Stele becomes interactable again after the result")
	# The strict boundary: exactly the threshold fails after all three rounds.
	save._config.set_value("steles", String(Chapter1WindRoom.COMBAT_ID), MinigameStele.SteleState.UNLOCKED)
	save.progress_changed.emit()
	trial = start()
	for i in room.combat_hit_limit:
		room.player.combat_stats.apply_health_damage(1)
	check(room.combat_active, "Reaching injury limit keeps the remaining rounds playable")
	tick(80.0)
	check(not room.combat_active and room.combat.state == MinigameStele.SteleState.UNLOCKED, "Exactly the injury limit fails and grants no completion")
	trial = start()
	tick(13.0)
	check(room.player.is_jump_blocked(), "Retry reaches downward flow")
	room.player.position = Vector2.ZERO
	room._update_combat(0.1)
	check(not room.combat_active and room.player.combat_winds.is_empty() and not room.player.is_jump_blocked(), "Leaving the platform interrupts and releases every movement restriction")
	trial = start()
	tick(1.0)
	room.respawn()
	check(not room.combat_active and room.player.combat_winds.is_empty(), "Fall or death respawn cancels the trial")
	# Scene removal must also release source registrations while player survives.
	trial = start()
	tick(13.0)
	room.remove_child(trial)
	check(room.player.combat_winds.is_empty() and not room.player.is_jump_blocked(), "Unexpected bird removal restores movement")
	trial.free()
	room.end_combat(false)
	# Existing 140 px/s combat winds keep their original cap after this opt-in.
	room.player.set_combat_wind(room, 200.0)
	check(room.player.horizontal_combat_wind() == 140.0, "Ordinary combat sources retain the established wind cap")
	room.player.clear_combat_wind(room)
	trial = start()
	room.player.set_combat_wind(room, 20.0)
	room.player.set_jump_blocked(room, true)
	tick(1.0)
	room.end_combat(false)
	check(room.player.horizontal_combat_wind() == 20.0 and room.player.is_jump_blocked(), "Trial cleanup preserves restrictions owned by other sources")
	room.player.clear_combat_wind(room)
	room.player.set_jump_blocked(room, false)
	trial = start()
	room.set_physics_process(true)
	paused = true
	var paused_age := trial.state_age
	await frames(5)
	check(trial.state_age == paused_age, "Tree pause freezes the real trial physics clock")
	paused = false
	await frames(5)
	check(trial.state_age > paused_age, "Resuming advances the real trial physics clock")
	room.set_physics_process(false)
	room.end_combat(false)
	# Editor movement of the arena changes the challenge and hazard bounds.
	var platform := room.get_node("Terrain/Arena") as TerrainPiece
	platform.position += Vector2(50, 20)
	room.player.reset_after_map_fall(platform.position + Vector2(440, 0))
	room._challenge(Chapter1WindRoom.COMBAT_ID, 1)
	check(room.arena_rect.position.is_equal_approx(platform.position - Vector2(0, 230)), "Trial bounds follow the platform edited in Godot")
	room.end_combat(false)
	print("WIND COMBAT: %d failures" % failures)
	quit(1 if failures else 0)
