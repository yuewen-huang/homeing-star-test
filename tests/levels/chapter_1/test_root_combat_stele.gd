extends SceneTree

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	func show_toast(_message: String) -> void: pass

var room: Chapter1RootRoom
var player: LanPlayer
var stele: MinigameStele
var save: MemoryProgress
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(count: int, speed := 1.0) -> void:
	for frame in count:
		if room.combat_active: room._update_combat(speed / 60.0)

func capture(label: String) -> void:
	if output.is_empty(): return
	room._update_camera()
	room.camera.reset_smoothing()
	room.camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Godot capture " + label)

func at_stele() -> void:
	player.reset_after_map_fall(Vector2(4519, 1890))
	player.combat_stats.restore_health()
	player.combat_stats.restore_poise()
	room.water.snap_to_level(RootWater.LOW)
	room._update_checkpoint()

func hold_casts() -> void:
	for tree in room._enemies:
		tree._clear_volleys()
		tree.cast_age = -1.0
		tree._next_cast = INF

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT") if DisplayServer.get_name() != "headless" else ""
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	save = MemoryProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	room = load("res://scenes/levels/chapter_1/chapter_1_root_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	player = room.player
	player.set_physics_process(false)
	room.water.set_physics_process(false)
	stele = room.get_node("Steles/CombatStele") as MinigameStele
	at_stele()
	check(not room.combat_active and room._enemies.is_empty(), "no treants spawn before the battle is activated")
	check(stele.interact() and stele.state == MinigameStele.SteleState.UNLOCKED and not room.combat_active, "first E unlocks and saves without starting combat")
	check(stele.interact() and room.combat_active and room._enemies.size() == 3, "second E starts exactly three stationary treants")
	stele.interact()
	check(room._enemies.size() == 3 and room._combat_root.get_child_count() == 3, "repeated activation cannot duplicate encounter")
	check(room._winches.all(func(winch: RootWaterWinch) -> bool: return winch.locked), "water winches are locked for the encounter")
	var starts: Array[Vector2] = []
	for index in 3:
		var tree := room._enemies[index]
		var ledge := room.get_node(Chapter1RootRoom.COMBAT_LEDGES[index]) as RootRockBlock
		starts.append(tree.position)
		check(tree.position == ledge.position + Vector2(ledge.size.x * 0.5, 0) and tree.tier == index, "tier %d stands at the existing ledge centre and foot anchor" % index)
		check(tree._sprite.texture == DeerVineTreant.WALK_TEXTURE and tree._sprite.offset == -DeerVineTreant.PIVOT and tree._sprite.hframes == 4 and tree._sprite.vframes == 4, "tier %d reuses the authored 16-frame treant sheet" % index)
	tick(90)
	check(room._enemies[0].casts == 1 and room._enemies[1].casts == 0 and room._enemies[2].casts == 0, "lowest treant releases first; higher casts are staggered")
	tick(60)
	check(room._enemies.all(func(tree: RootCombatTreant) -> bool: return tree.casts == 1), "all three treants repeatedly use their real casting animation")
	for index in 3:
		var tree := room._enemies[index]
		var volley := tree.volleys[0] as DeerRootVolley
		check(tree.position == starts[index] and tree._sprite.scale == Vector2.ONE * 1.4, "tier %d stays on its ledge at authored scale" % index)
		check(volley.profile == RootCombatTreant.SPIKE_KINDS[index] and String(volley._spikes[0].key).begins_with(volley.profile) and volley.ground_y == 1890, "tier %d selects matching painted roots on the lower platform" % index)
		check(volley.attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER and volley.get_parent() == room._combat_root, "tier %d shares gold danger rules and encounter ownership" % index)
	check(room.arena_rect.has_point(Vector2(5060, 1240)), "arena includes double-jump headroom above upper treant")
	await capture("root_treants_overview")
	tick(190)
	check(room._enemies.all(func(tree: RootCombatTreant) -> bool: return tree.casts >= 2), "casters continue releasing spikes until killed")
	hold_casts()
	var painted: Array[DeerRootVolley] = []
	for index in 3:
		player.position.x = 4610 + index * 170
		painted.append(room._enemies[index].cast_spikes() as DeerRootVolley)
	at_stele()
	tick(21)
	check(painted.all(func(volley: DeerRootVolley) -> bool: return volley.active_rects().is_empty()), "all profiles warn before dealing damage")
	await capture("root_spikes_warning")
	var times: Array[float] = []
	for volley in painted: times.append(volley._time)
	player.input_frozen = true
	tick(60)
	check(is_equal_approx(painted[0]._time, times[0]) and is_equal_approx(painted[2]._time, times[2]), "frozen combat pauses all painted roots and their warnings")
	player.input_frozen = false
	tick(43)
	var heights: Array[float] = []
	for volley in painted: heights.append(volley.active_rects()[0].size.y)
	check(heights[0] < heights[1] and heights[1] < heights[2], "short, medium and high roots retain visibly different authored heights")
	await capture("root_spikes_active")
	var locked_x: float = painted[0]._spikes[0].x
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var previous_invincible := assist.player_invincible
	assist.set_player_invincible(false)
	player.reset_after_map_fall(Vector2(locked_x, 1890))
	painted[0]._resolve_hit()
	check(player.combat_stats.health == 92, "painted low root deals real eight-HP damage at the lower platform")
	painted[0]._resolve_hit()
	check(player.combat_stats.health == 92, "one root cast cannot deal repeated damage to its target")
	player.reset_after_map_fall(Vector2(locked_x + 200, 1760))
	check(painted[0]._spikes[0].x == locked_x and painted[0].ground_y == 1890, "moving or climbing cannot relocate a committed root or change its floor")
	at_stele()
	tick(36)
	check(painted.all(func(volley: DeerRootVolley) -> bool: return volley.active_rects().is_empty()), "all roots close damage during recovery")
	await capture("root_spikes_recovery")
	for speed in [0.25, 0.5, 1.0]:
		hold_casts()
		var tree := room._enemies[0]
		var volley := tree.cast_spikes() as DeerRootVolley
		tick(roundi(0.75 * 60 / speed), speed)
		check(volley.active_rects().is_empty(), "warning stays harmless at speed %.2f" % speed)
		tick(roundi(0.30 * 60 / speed), speed)
		check(not volley.active_rects().is_empty(), "painted active window synchronizes at speed %.2f" % speed)
	hold_casts()
	var middle := room._enemies[1]
	var cancelled := middle.cast_spikes() as DeerRootVolley
	middle.receive_hit(1, player.global_position)
	middle.receive_hit(1, player.global_position)
	check(middle.has_poise_bar() and middle.is_poise_broken() and middle.combat_stats.health == 16 and cancelled.cancelled and cancelled.active_rects().is_empty(), "shared normal attacks break poise and immediately cancel pending spikes")
	player.reset_after_map_fall(middle.position + Vector2(-40, 0))
	player.apply_attack_facing(1)
	player.perform_special_attack(1, 0.0, player.find_throw_target())
	var effect := player.timeline_attack_effect
	effect.set_process(false)
	check(player.special_attack_max_form and effect.skill_hit_context.max_form, "E throw selects the existing PLUS against a broken treant")
	middle.receive_skill_hit(effect.skill_hit_context, player.global_position)
	player.cancel_uncommitted_attack_effects()
	check(middle.dead and room.combat_active and room._remaining_treants == 2, "one kill does not complete the three-target objective")
	at_stele()
	room._enemies[2].receive_hit(10, player.global_position)
	check(room.combat_active and room._remaining_treants == 1, "two kills still leave the challenge active")
	room._enemies[0].receive_hit(10, player.global_position)
	check(not room.combat_active and stele.state == MinigameStele.SteleState.COMPLETED and save.get_stele_state(Chapter1RootRoom.COMBAT_ID) == 2, "third kill completes and saves the combat stele")
	check(room._enemies.is_empty() and room._winches.all(func(winch: RootWaterWinch) -> bool: return not winch.locked), "victory clears encounter and releases winches")
	check(not stele.challenge_available and stele._info_label.text.contains("E 存档"), "completed stele offers saving instead of an unavailable challenge")
	await process_frame
	await capture("root_combat_complete")
	stele.interact()
	check(not room.combat_active, "completed stele cannot respawn the three treants")
	# Failure fixtures reset only the test's in-memory completion state.
	save._config.set_value("steles", String(Chapter1RootRoom.COMBAT_ID), 1)
	save.progress_changed.emit()
	at_stele()
	stele.interact()
	tick(150)
	var old_host := room._combat_root
	var abandoned := room._enemies[0].volleys[0] as DeerRootVolley
	player.position = Vector2(4050,1890)
	room._update_combat(0)
	check(not room.combat_active and abandoned.cancelled and room._enemies.is_empty() and stele.state == MinigameStele.SteleState.UNLOCKED, "leaving local arena cancels roots without granting completion")
	await process_frame
	check(not is_instance_valid(old_host), "aborted encounter removes the entire owned subtree")
	at_stele()
	stele.interact()
	tick(30)
	check(room._enemies.size() == 3 and room._enemies[0].health == 32, "retry recreates three undamaged casters")
	hold_casts()
	var fatal := room._enemies[0].cast_spikes() as DeerRootVolley
	fatal._time = RootCombatTreant.WARN_TIME + 0.25
	player.combat_stats.health = 1
	fatal._resolve_hit()
	check(player.combat_stats.health == 0 and not room.combat_active and fatal.cancelled, "lethal spike safely cancels encounter from inside damage settlement")
	await process_frame
	check(player.combat_stats.health == 100 and player.combat_stats.poise == 100 and stele.state == MinigameStele.SteleState.UNLOCKED, "death restores player at checkpoint and permits E retry")
	at_stele()
	stele.interact()
	tick(30)
	player.position.y = room.water.surface_y + RootWater.DROWN_DEPTH + 1
	check(room.water.is_player_drowning(), "drowning fixture is inside the real water region")
	room._process(0)
	check(not room.combat_active and room._enemies.is_empty() and room._winches.all(func(winch: RootWaterWinch) -> bool: return not winch.locked), "drowning also cancels the encounter and unlocks winches")
	assist.set_player_invincible(previous_invincible)
	save.set_stele_state(Chapter1RootRoom.COMBAT_ID, 2)
	current_scene = null
	room.free()
	await process_frame
	room = load("res://scenes/levels/chapter_1/chapter_1_root_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.set_process(false)
	room.player.set_physics_process(false)
	room.start_combat()
	check(room._combat_stele.state == MinigameStele.SteleState.COMPLETED and not room.combat_active and room._enemies.is_empty(), "loading completed state never spawns combat actors")
	current_scene = null
	room.free()
	await process_frame
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "regression preserves real story save bytes")
	print("ROOT COMBAT STELE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
