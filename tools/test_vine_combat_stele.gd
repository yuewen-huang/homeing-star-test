extends SceneTree

class MemoryProgress extends SaveProgressService:
	var writes_fail := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not writes_fail
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	func show_toast(_message: String) -> void: pass

var room: Chapter1VineRoom
var player: LanPlayer
var save: MemoryProgress
var checks := 0
var failures := 0
var output := ""
var assist: BattleAssistSettingsService

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(seconds: float, speed := 1.0) -> void:
	for frame in roundi(seconds * 60 / speed):
		if room.combat_active: room._update_combat(speed / 60)

func at_stele() -> void:
	player.reset_after_map_fall(room.combat.global_position + Vector2(-45, 0))
	player.combat_stats.restore_health()
	player.combat_stats.restore_poise()
	room._checkpoint = player.position

func hold_attacks() -> void:
	for enemy in room._enemies:
		if enemy.dead: continue
		enemy._stop_attack()
		enemy.state = VineCombatEnemy.State.IDLE
		enemy.next_attack = INF
		enemy.tip = enemy.home
		enemy._update_pose()

func reset_challenge() -> void:
	if room.combat_active: room.end_combat(false)
	save._config.set_value("steles", String(Chapter1VineRoom.COMBAT_ID), 1)
	save.progress_changed.emit()
	at_stele()
	room.start_combat()
	hold_attacks()

func capture(label: String) -> void:
	if output.is_empty(): return
	room._process(0)
	room._update_camera()
	room.camera.reset_smoothing()
	room.camera.force_update_scroll()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Godot capture " + label)

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
	assist = root.get_node("BattleAssist") as BattleAssistSettingsService
	var was_invincible := assist.player_invincible
	var previous_mode := assist.difficulty
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/sideview/chapter_1_vine_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	player = room.player
	player.set_physics_process(false)
	at_stele()
	var paths := [room.combat_reel_vine, room.combat_pierce_vine, room.combat_slash_vine]
	var originals: Array[VineTrialPiece] = []
	var positions: Array[Vector2] = []
	var lengths: Array[float] = []
	for path in paths:
		var vine := room.get_node(path) as VineTrialPiece
		originals.append(vine)
		positions.append(vine.position)
		lengths.append(vine.vine_length)
	check(not room.combat_active and originals.all(func(v: VineTrialPiece) -> bool: return v.combat_path.is_empty() and player.vines.has(v)), "all three vines retain normal traversal before activation")
	await capture("vine_combat_0_normal")
	check(room.combat.interact() and not room.combat_active and room.combat.state == MinigameStele.SteleState.UNLOCKED, "first E unlocks without activating vines")
	check(room.combat.interact() and room.combat_active and room._enemies.size() == 3, "second E activates exactly the three configured map vines")
	room.combat.interact()
	check(room._enemies.size() == 3 and room._combat_root.get_child_count() == 3, "repeat activation cannot duplicate living vines")
	for index in 3:
		var enemy := room._enemies[index]
		var vine := originals[index]
		check(enemy.vine == vine and vine.position == positions[index] and vine.vine_length == lengths[index], "role %d keeps original map anchor and length" % index)
		check(not vine.combat_path.is_empty() and not player.vines.has(vine) and is_inf(vine.vine_grab_point(Vector2.ZERO).x), "role %d disables automatic grabbing only while alive" % index)
		check(enemy._hurtbox.is_in_group(&"hurtbox") and enemy.has_poise_bar() and enemy._stem_shapes.size() == 8, "role %d shares sword, skill and poise contracts along its body" % index)
	tick(1.2)
	check(room._enemies[0].casts == 1 and room._enemies[1].casts == 0, "first pull is staggered before piercing and slashing")
	await capture("vine_combat_1_awake")
	# Deterministic action samples: all three warnings, real motion and recovery.
	for index in 3:
		hold_attacks()
		at_stele()
		var enemy := room._enemies[index]
		enemy.begin_attack()
		var locked := enemy.aim
		tick(0.4)
		check(enemy.state == VineCombatEnemy.State.WARNING and enemy._hitbox.attack == null, "role %d warning is harmless" % index)
		await capture("vine_role_%d_warning" % index)
		var before := enemy.state_time
		player.input_frozen = true
		tick(1.0)
		check(enemy.state_time == before, "role %d pauses its warning with combat" % index)
		player.input_frozen = false
		player.position.x += 250
		tick(0.5)
		check(enemy.aim == locked and enemy.state == VineCombatEnemy.State.STRIKE, "role %d commits its aim and moves the actual vine" % index)
		await capture("vine_role_%d_active" % index)
		tick(0.5)
		check(enemy.state == VineCombatEnemy.State.RECOVERY and enemy._hitbox.attack == null, "role %d closes damage during recovery" % index)
		await capture("vine_role_%d_recovery" % index)
	# The real pull connects, displaces horizontally, and releases on time.
	hold_attacks()
	at_stele()
	var reel := room._enemies[0]
	reel.begin_attack()
	var before_x := player.position.x
	tick(1.05)
	check(reel.state == VineCombatEnemy.State.PULL and player.combat_anchor_owner == reel, "reel vine catches the player through real contact")
	tick(0.3)
	check(player.position.x > before_x + 50 and player.position.x <= reel.home.x and player.position.y == 1360 and player.combat_stats.health == 100, "pull moves toward the reel without HP damage or leaving the platform")
	await capture("vine_reel_pulling")
	tick(1.0)
	check(not player.is_combat_anchored(), "pull always releases its control")
	hold_attacks()
	at_stele()
	reel.begin_attack()
	tick(1.05)
	reel.receive_hit(99, player.position)
	check(reel.dead and not player.is_combat_anchored() and originals[0].combat_path.is_empty() and player.vines.has(originals[0]), "killing a pulling vine immediately restores normal traversal and releases the player")
	check(room.combat_active and room._remaining_vines == 2, "one defeated vine leaves the other two active")
	# The other attack role deals real damage through its horizontal sweep.
	hold_attacks()
	at_stele()
	var slash := room._enemies[2]
	slash.begin_attack()
	tick(1.4)
	check(player.combat_stats.health == 92, "ordinary vine slash damages the player once across the warned strip")
	# Piercing uses ordinary damage, half guard, parry and shared contact assist.
	var pierce := room._enemies[1]
	hold_attacks()
	at_stele()
	pierce.begin_attack()
	tick(1.2)
	check(player.combat_stats.health == 92, "pierce deals exactly eight HP through its moving tip")
	tick(0.05)
	check(player.combat_stats.health == 92, "one piercing attack cannot damage twice")
	hold_attacks()
	at_stele()
	player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	pierce.begin_attack()
	tick(1.2)
	check(player.combat_stats.health == 96, "ordinary guard retains the shared half-damage rule")
	hold_attacks()
	at_stele()
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	pierce.begin_attack()
	tick(1.2)
	check(player.combat_stats.health == 100 and pierce.combat_stats.poise == 5 and pierce.state == VineCombatEnemy.State.RECOVERY, "parry interrupts piercing and removes shared 25 poise")
	hold_attacks()
	at_stele()
	player.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	pierce.begin_attack()
	for frame in 72:
		if pierce.is_poise_broken(): break
		tick(1.0 / 60)
	check(pierce.is_poise_broken() and player.combat_stats.health == 100, "second parry breaks the piercing vine's poise")
	tick(2.1)
	check(not pierce.is_poise_broken() and pierce.combat_stats.poise == 30, "poise recovery resumes attacks after the shared stagger")
	hold_attacks()
	at_stele()
	pierce.begin_attack()
	tick(1.25)
	check(player.combat_stats.health == 92, "an unparried piercing contact deals its damage once")
	# Max and actual skill damage are available against a broken vine.
	pierce.receive_hit(1, player.position)
	pierce.receive_hit(1, player.position)
	pierce.receive_hit(1, player.position)
	check(pierce.is_poise_broken() and pierce.combat_stats.health == 8, "three sword hits break poise and leave a damage window")
	player.reset_after_map_fall(pierce.tip + Vector2(-40, 60))
	player.apply_attack_facing(1)
	player.perform_special_attack(1, 0.0, player.find_throw_target())
	var effect := player.timeline_attack_effect
	effect.set_process(false)
	check(player.special_attack_max_form and effect.skill_hit_context.max_form, "E throw selects the existing PLUS against a broken vine")
	pierce.receive_skill_hit(effect.skill_hit_context, player.position)
	player.cancel_uncommitted_attack_effects()
	check(pierce.dead and room._remaining_vines == 1 and room.combat_active, "skill damage restores the second vine without completing early")
	# Saving failure retains the won result and does not reactivate vines.
	save.writes_fail = true
	room._enemies[2].receive_hit(99, player.position)
	check(not room.combat_active and room._completion_pending and originals.all(func(v: VineTrialPiece) -> bool: return v.combat_path.is_empty() and player.vines.has(v)), "third defeat restores every vine and retains victory on save failure")
	save.writes_fail = false
	at_stele()
	room.combat.interact()
	check(not room._completion_pending and room.combat.state == MinigameStele.SteleState.COMPLETED and not room.combat.challenge_available, "E retries the completion save without another fight")
	# Let shared Max speed-lines and impact feedback finish before the still.
	for frame in 60: await process_frame
	await capture("vine_combat_complete")
	room._challenge(Chapter1VineRoom.COMBAT_ID, 1)
	check(not room.combat_active, "completed progress cannot reactivate vines")
	# Pause / slow action time and failed-attempt cleanup.
	for speed in [0.25, 0.5, 1.0]:
		reset_challenge()
		pierce = room._enemies[1]
		pierce.begin_attack()
		tick(0.7, speed)
		check(pierce.state == VineCombatEnemy.State.WARNING, "warning follows action seconds at %.2f speed" % speed)
		tick(0.2, speed)
		check(pierce.state == VineCombatEnemy.State.STRIKE, "active motion follows action seconds at %.2f speed" % speed)
	reset_challenge()
	reel = room._enemies[0]
	reel.begin_attack()
	tick(1.05)
	player.position.x = room.arena_rect.end.x + 100
	room._update_combat(0)
	check(not room.combat_active and not player.is_combat_anchored() and originals.all(func(v: VineTrialPiece) -> bool: return v.combat_path.is_empty() and player.vines.has(v)), "leaving the local arena cancels all attacks and releases pull")
	reset_challenge()
	reel = room._enemies[0]
	reel.begin_attack()
	tick(1.05)
	room._on_death()
	check(not room.combat_active and not player.is_combat_anchored(), "death cancels the encounter immediately inside contact settlement")
	await process_frame
	check(player.combat_stats.health == 100 and player.combat_stats.poise == 100, "death restores health and poise for retry")
	reset_challenge()
	pierce = room._enemies[1]
	player.combat_stats.health = 1
	pierce.begin_attack()
	tick(1.2)
	check(not room.combat_active and player.combat_stats.health == 0 and originals.all(func(v: VineTrialPiece) -> bool: return v.combat_path.is_empty()), "lethal piercing safely cancels the encounter from inside actual damage settlement")
	await process_frame
	check(player.combat_stats.health == 100 and not player.is_combat_anchored(), "lethal piercing revives cleanly without retaining control")
	reset_challenge()
	check(room._enemies.size() == 3 and room._enemies.all(func(e: VineCombatEnemy) -> bool: return e.combat_stats.health == 32), "retry reactivates all three vines at full health")
	room.end_combat(false)
	for index in 3:
		check(originals[index].position == positions[index] and originals[index].vine_length == lengths[index] and originals[index].is_processing(), "cleanup preserves vine %d authored position, length and normal updates" % index)
	reset_challenge()
	reel = room._enemies[0]
	reel.begin_attack()
	tick(1.05)
	current_scene = null
	room.free()
	await process_frame
	check(not is_instance_valid(player), "scene exit removes the encounter")
	save.set_stele_state(Chapter1VineRoom.COMBAT_ID, 2)
	room = load("res://scenes/sideview/chapter_1_vine_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.start_combat()
	check(not room.combat_active and room._enemies.is_empty() and not room.combat.challenge_available, "loading completed progress keeps all vines in their ordinary state")
	current_scene = null
	room.free()
	assist.set_player_invincible(was_invincible)
	assist.set_difficulty(previous_mode)
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "all checks preserve the real story save bytes")
	print("VINE COMBAT STELE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
