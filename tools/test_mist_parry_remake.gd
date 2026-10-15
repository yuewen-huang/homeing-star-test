extends SceneTree

class TestProgress extends SaveProgressService:
	var fail_writes := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return not fail_writes
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

class SkillHit extends RefCounted:
	var damage := 9999

var failures := 0
var save: TestProgress
var room: Node2D
var user_save: PackedByteArray
var qte: ContactParryQTE

func _initialize() -> void:
	user_save = FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1

func frames(n: int) -> void:
	for i in n:
		await physics_frame

func press_k() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.keycode = KEY_K
	key.pressed = true
	root.push_input(key)
	key = InputEventKey.new()
	key.physical_keycode = KEY_K
	key.keycode = KEY_K
	root.push_input(key)
	await frames(2)

func prepare_contact(enemy: MistParryEnemy) -> void:
	qte.cancel()
	var target: LanPlayer = room.player
	target.finish_defense()
	target.combat_stats.restore_health()
	target.resync_held_input_state()
	target.play_idle()
	enemy.global_position = target.global_position + Vector2(24, 0)
	enemy.floor_y = target.position.y
	enemy._begin_warning()
	enemy._begin_charge()
	enemy._physics_process(1.0 / 60.0)

func finish_appearance(enemy: MistParryEnemy) -> void:
	enemy._physics_process(MistParryEnemy.PARRY_PAUSE + 0.01)

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	qte = root.get_node("ParryQTE") as ContactParryQTE
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	transition.set_scene_entry_position(Vector2(1800, 555))
	room = load("res://scenes/sideview/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	check(room.mist_enemies.is_empty(), "Mist stays peaceful before combat stele interaction")
	save.set_stele_state(room.COMBAT_ID, MinigameStele.SteleState.UNLOCKED)
	room._combat_stele_requested(room.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	for enemy: MistParryEnemy in room.mist_enemies:
		enemy.set_physics_process(false)
	check(room.ROOM_SIZE.x == 3840 and room.player.world_max_x == 3792, "Mist shortened from twelve screens to three")
	check(room.mist_enemies.size() == 3, "Exactly one persistent opponent of each species")
	check(room.get_node("CombatStele").stele_id == &"mist_combat_01", "Existing combat stele ID retained")
	check(room.get_node("PortalToRoot").position.x < room.ROOM_SIZE.x, "Root exit is inside shortened map")

	# Waiting without movement triggers each independent timer, including overlaps.
	var initial: Vector2 = room.player.position
	var sides := {}
	var waits := {}
	for seed_value in 20:
		for enemy: MistParryEnemy in room.mist_enemies:
			enemy.reset_challenge()
			enemy._rng.seed = seed_value * 13 + enemy.species
			waits[enemy._spawn_wait] = true
			enemy._spawn_wait = 0.001
			enemy._physics_process(0.01)
			sides[signf(enemy.position.x - initial.x)] = true
			check(enemy.state == MistAmbusher.State.WARNING, "Stationary spawn, species %d seed %d" % [enemy.species, seed_value])
		check(room.mist_enemies.all(func(e): return e.state == MistAmbusher.State.WARNING), "Three simultaneous appearances allowed")
	check(room.player.position == initial and sides.size() == 2 and waits.size() > 1, "Random delays and left/right spawns without moving")

		# Physical K input also works without assisted contact prompts.
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.NONE)
	var manual := MistParryEnemy.new()
	manual.setup(room.player, MistAmbusher.Species.BOAR, room.player.position + Vector2(24,0))
	room.add_child(manual)
	manual.set_physics_process(false)
	room.player.set_physics_process(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.keycode = KEY_K
	key.pressed = true
	Input.parse_input_event(key)
	for i in 120:
		await frames(1)
		if room.player.defense_state == LanPlayer.DefenseState.PARRY_ACTIVE: break
	key = InputEventKey.new()
	key.physical_keycode = KEY_K
	key.keycode = KEY_K
	Input.parse_input_event(key)
	manual._begin_warning()
	manual._begin_charge()
	await frames(3)
	check(manual.parry_count == 1 and manual.state == MistAmbusher.State.RECOVERY, "Physical K manually parries without QTE assistance")
	manual.queue_free()
	room.player.set_physics_process(false)
	room.player.finish_defense()
	room.player.resync_held_input_state()
	await frames(10)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)

	# All standard damage interfaces are immune, including while charging / in QTE.
	var defeated_counts := {}
	for enemy: MistParryEnemy in room.mist_enemies:
		defeated_counts[enemy.species] = 0
		enemy.defeated.connect(func(e): defeated_counts[e.species] += 1)
		enemy.reset_challenge()
		enemy._begin_warning()
		var before := enemy.health
		enemy.receive_hit(9999, room.player.position)
		enemy.receive_skill_hit(SkillHit.new(), room.player.position)
		check(enemy.health == before and enemy.parry_count == 0 and enemy.state == MistAmbusher.State.WARNING, "J / skill / ultimate damage cannot interrupt or hurt species %d" % enemy.species)
		prepare_contact(enemy)
		check(enemy.state == MistAmbusher.State.QTE and qte.is_owner(enemy), "Real contact opens K prompt")
		enemy.receive_hit(9999, room.player.position)
		check(qte.is_owner(enemy) and enemy.health == before, "Normal damage does not cancel K prompt")
		var attack: CombatAttackData = enemy.attack_data
		var stopped_at := enemy.position
		await press_k()
		check(enemy.parry_count == 1 and enemy.health == before - 1 and enemy.state == MistAmbusher.State.RECOVERY, "Actual K counts one parry and stops species %d" % enemy.species)
		enemy.on_attack_parried(attack, room.player.position)
		enemy._on_attack_hit_resolved(room.player, CombatHitResult.Type.PARRY_SUCCESS)
		check(enemy.parry_count == 1, "One attack cannot count twice")
		enemy._physics_process(0.1)
		check(enemy.position == stopped_at and enemy.state == MistAmbusher.State.RECOVERY, "Parried enemy stays still before disappearing")
		finish_appearance(enemy)
		check(enemy.state == MistAmbusher.State.HIDDEN and not enemy.animated_sprite.visible and enemy.parry_count == 1, "Disappears in place and retains cumulative parries")

	# A missed attack must continue past its original duration and vanish off-view.
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.NONE)
	for enemy: MistParryEnemy in room.mist_enemies:
		enemy.position = room.player.position + Vector2(200, 0)
		enemy.floor_y = 555
		enemy._begin_warning()
		enemy._begin_charge()
		room.player.position.y = 280 # miss without synthesizing a parry
		var before := enemy.parry_count
		enemy._update_charge(enemy._charge_duration + 0.01)
		check(enemy.state == MistAmbusher.State.CHARGE, "Miss keeps charging past old duration")
		for i in 180:
			enemy._physics_process(1.0 / 60.0)
			if enemy.state == MistAmbusher.State.HIDDEN:
				break
		check(enemy.state == MistAmbusher.State.HIDDEN and enemy._outside_visibility() and enemy.parry_count == before, "Miss disappears outside visibility without counting")
		room.player.position.y = 555

	# Two overlapping contacts share one prompt and can be parried sequentially.
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)
	var first: MistParryEnemy = room.mist_enemies[0]
	var second: MistParryEnemy = room.mist_enemies[1]
	prepare_contact(first)
	second.position = room.player.position + Vector2(-24, 0)
	second._begin_warning()
	second._begin_charge()
	second._physics_process(0.016)
	check(qte.is_owner(first) and second.state == MistAmbusher.State.CHARGE and not second.attack_hitbox.monitoring, "Overlap preserves one prompt and blocks other hitbox")
	await press_k()
	room.player.finish_defense()
	second._physics_process(0.016)
	check(qte.is_owner(second), "Second overlapping enemy can offer next K prompt")
	await press_k()
	finish_appearance(first)
	finish_appearance(second)

	save.fail_writes = true
	for enemy: MistParryEnemy in room.mist_enemies:
		var target: int = MistParryEnemy.REQUIRED_PARRIES[enemy.species]
		while enemy.parry_count < target:
			prepare_contact(enemy)
			await press_k()
			if enemy.parry_count == target:
				check(enemy.state == MistAmbusher.State.RECOVERY and defeated_counts[enemy.species] == 0, "Final K pauses before reporting defeat")
			finish_appearance(enemy)
		check(enemy.state == MistAmbusher.State.DEAD and defeated_counts[enemy.species] == 1, "Species defeated once after %d parries" % target)
		enemy._physics_process(10)
		check(enemy.state == MistAmbusher.State.DEAD and defeated_counts[enemy.species] == 1, "Defeated species never respawns")
	check(room._completion_pending and save.get_stele_state(room.COMBAT_ID) != 2, "Failed completion save rolls back and stays retryable")
	save.fail_writes = false
	room._combat_stele_requested(room.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	check(not room._completion_pending and save.get_stele_state(room.COMBAT_ID) == 2 and room.get_node("CombatStele").state == MinigameStele.SteleState.COMPLETED, "All three defeated completes only combat stele after successful retry")
	check(save.get_stele_state(&"mist_puzzle_entry") == 0, "Combat does not complete rune puzzle")
	room.queue_free()
	await process_frame
	transition.set_scene_entry_position(Vector2(15080,555))
	room = load("res://scenes/sideview/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	check(room.player.position.is_equal_approx(room.ROOT_ENTRY), "Legacy eastern arrival maps to safe new entrance")
	check(room.mist_enemies.all(func(e): return e.state == MistAmbusher.State.DEAD), "Completed save does not respawn defeated species")
	var arena_enemy := RootArenaEnemy.new()
	arena_enemy.setup_arena(room.player, MistAmbusher.Species.RAT, room.player.position + Vector2(80, 0), 555, 0, 3840)
	room.add_child(arena_enemy)
	arena_enemy.set_physics_process(false)
	arena_enemy._begin_warning()
	arena_enemy.receive_hit(1, room.player.position)
	check(arena_enemy.health == 1, "Root / wind / vine arena enemies retain normal damage")
	arena_enemy.queue_free()
	room.queue_free()
	await frames(10)
	check(user_save == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "Player save bytes unchanged")
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	(root.get_node("CombatFeedback") as CombatFeedbackService).impact_player.stop()
	await frames(10)
	print("MIST PARRY REMAKE: %d failures" % failures)
	quit(1 if failures else 0)
