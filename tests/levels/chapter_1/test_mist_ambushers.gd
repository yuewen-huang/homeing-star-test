extends SceneTree

class UnlockedProgress extends SaveProgressService:
	func _ready() -> void:
		pass
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

class Arena extends Node2D:
	pass

class StoryProgress extends SaveProgressService:
	func _ready() -> void:
		_loaded = true

var arena: Arena
var player: LanPlayer
var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func settle() -> void:
	for i in range(6):
		await physics_frame

func new_arena() -> void:
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	if is_instance_valid(arena):
		arena.queue_free()
		await process_frame
	Engine.time_scale = 1.0
	arena = Arena.new()
	root.add_child(arena)
	current_scene = arena
	var camera := Camera2D.new()
	camera.position = Vector2(1000,360)
	arena.add_child(camera)
	camera.make_current()
	player = load("res://scenes/player/lan/lan_player.tscn").instantiate() as LanPlayer
	player.world_min_x = -10000.0
	player.world_max_x = 20000.0
	player.fallback_ground_y = 555.0
	player.position = Vector2(1000,555)
	arena.add_child(player)
	var progress := UnlockedProgress.new()
	player.add_child(progress)
	player.save_progress = progress
	player.save_progress_resolved = true
	player.set_physics_process(false)
	player.get_node("SkillBar").hide()
	player.get_node("PlayerStatusHUD").hide()
	await process_frame

func spawn_enemy(kind: MistAmbusher.Species, offset := 30.0) -> MistAmbusher:
	var enemy := MistAmbusher.new()
	enemy.setup(player, kind, Vector2(player.position.x + offset,555))
	arena.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func prepare_charge(enemy: MistAmbusher) -> void:
	enemy._begin_warning()
	enemy._begin_charge()
	enemy._update_visibility()

func run_tests() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await capture_gameplay()
		return
	for kind in [MistAmbusher.Species.BOAR, MistAmbusher.Species.RAT, MistAmbusher.Species.BEE]:
		await new_arena()
		var enemy := spawn_enemy(kind, 600.0)
		check(enemy.state == MistAmbusher.State.HIDDEN and not enemy.animated_sprite.visible and not enemy.hurtbox.monitorable, "Hidden enemy leaks visuals/hurtbox")
		enemy.receive_hit(20, player.global_position)
		check(enemy.health > 0, "Unrevealed bush enemy must not be hit")
		enemy._physics_process(0.016)
		check(enemy.warning_count == 0, "Warning outside trigger radius")
		player.position.x += 199.0
		enemy._physics_process(0.016)
		check(enemy.state == MistAmbusher.State.HIDDEN, "Warning must not trigger at 401px")
		player.position.x += 2.0
		enemy._physics_process(0.016)
		check(enemy.state == MistAmbusher.State.WARNING and enemy.warning_count == 1 and enemy.warning_audio.playing, "399px warning/audio not triggered")
		enemy._physics_process(0.1)
		check(enemy.warning_count == 1 and not enemy.animated_sprite.visible, "Warning repeats or reveals enemy in full fog")
		enemy._physics_process(1.0)
		check(enemy.state == MistAmbusher.State.CHARGE, "Warning does not lead to attack")
		var velocity := enemy._charge_velocity
		player.position.x += 500.0
		enemy._physics_process(0.01)
		check(enemy._charge_velocity == velocity, "Charge unfairly homes after launch")
		enemy._begin_recovery()
		enemy._physics_process(2.0)
		enemy.global_position = enemy.home
		enemy._physics_process(0.01)
		check(enemy.state == MistAmbusher.State.HIDDEN and not enemy._rearmed, "Recovery does not hide/rearm correctly")
		player.global_position = enemy.home
		enemy._physics_process(2.0)
		check(enemy.warning_count == 1, "Standing nearby retriggers warning spam")
		player.position.x = enemy.home.x + 501.0
		enemy._physics_process(0.01)
		check(enemy._rearmed, "Leaving trigger margin does not rearm")
		for direction in [-1.0,1.0]:
			await new_arena()
			(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
			enemy = spawn_enemy(kind, direction * 25.0)
			prepare_charge(enemy)
			await settle()
			check(player.combat_stats.health < player.combat_stats.max_health, "Normal collision did not damage player")
			var damaged_health := player.combat_stats.health
			await settle()
			check(player.combat_stats.health == damaged_health, "One charge damaged player twice")

			await new_arena()
			enemy = spawn_enemy(kind, direction * 25.0)
			player.start_parry(true)
			prepare_charge(enemy)
			await settle()
			check(player.combat_stats.health == player.combat_stats.max_health and enemy.state == MistAmbusher.State.RECOVERY, "Manual parry did not stop charge")

			await new_arena()
			enemy = spawn_enemy(kind, direction * 25.0)
			player.start_back_dodge(-direction)
			prepare_charge(enemy)
			await settle()
			check(player.combat_stats.health == player.combat_stats.max_health, "Roll invulnerability did not evade charge")

		await new_arena()
		enemy = spawn_enemy(kind)
		prepare_charge(enemy)
		enemy._physics_process(0.016)
		enemy.receive_hit(enemy.health, player.global_position)
		await settle()
		check(enemy.state == MistAmbusher.State.DEAD and not enemy.attack_hitbox.monitoring, "Death did not cancel attack")

	for kind in [MistAmbusher.Species.BOAR, MistAmbusher.Species.RAT, MistAmbusher.Species.BEE]:
		await new_arena()
		var story := StoryProgress.new()
		player.add_child(story)
		player.save_progress = story
		check(player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Fresh story unexpectedly unlocks K")
		var locked_enemy := spawn_enemy(kind,25.0)
		prepare_charge(locked_enemy)
		locked_enemy._physics_process(0.016)
		check(locked_enemy.state == MistAmbusher.State.CHARGE, "Locked K interrupted the charge")
		await settle()
		check(player.combat_stats.health < player.combat_stats.max_health, "Locked K suppressed ordinary damage")
		story._config.set_value(SaveProgressService.PROGRESS_SECTION, String(SaveProgressService.STORY_MASTER_PARRY_LEARNED), true)
		player.finish_hit_reaction()
		check(not player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Story milestone did not unlock K")
		locked_enemy._begin_recovery()

	arena.queue_free()
	await process_frame
	await test_full_room_ambush()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	Engine.time_scale = 1.0
	for i in range(10):
		await physics_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	(root.get_node("CombatFeedback") as CombatFeedbackService).impact_player.stop()
	await process_frame
	if failures == 0:
		print("PASS: three species / both directions; concealment, 400px audio warning, committed attack, rearm, one hit, manual defense, roll, locked K and death")
	quit(1 if failures else 0)



func capture_gameplay() -> void:
	var output := OS.get_cmdline_user_args()[-1]
	var room = load("res://scenes/levels/chapter_1/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	check(room.mist_enemies.size() == 3, "Mist room must contain three persistent opponents")
	var target := room.player as LanPlayer
	target.set_physics_process(false)
	var progress := UnlockedProgress.new()
	target.add_child(progress)
	target.save_progress = progress
	target.save_progress_resolved = true
	room.camera.position_smoothing_enabled = false
	for enemy: MistAmbusher in room.mist_enemies:
		enemy.set_physics_process(false)
		enemy.attack_hitbox.deactivate()
	for sample in ["hidden", "boar", "rat", "bee"]:
		for other: MistAmbusher in room.mist_enemies:
			other._hide_in_bush()
		var index := 2
		if sample == "rat":
			index = 0
		elif sample.begins_with("bee"):
			index = 1
		var enemy := room.mist_enemies[index] as MistAmbusher
		target.position = Vector2(enemy.home.x - (450.0 if sample == "hidden" else 75.0),555)
		target.play_idle()
		room.camera.position = Vector2(target.position.x,360)
		room.camera.reset_smoothing()
		room.camera.force_update_scroll()
		if sample != "hidden":
			enemy.position = target.position + Vector2(70.0, -22.0 if index == 2 else 0.0)
			enemy._begin_warning()
			enemy._begin_charge()
			enemy.attack_hitbox.deactivate()
			enemy.animated_sprite.pause()
			enemy.animated_sprite.frame = 2
			enemy._update_visibility()
		for i in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(output.path_join(sample + ".png"))
		check(result == OK, "Gameplay capture failed")
		print("Captured mist gameplay: ", sample)
	room.queue_free()
	await process_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	quit(1 if failures else 0)

func test_full_room_ambush() -> void:
	var room = load("res://scenes/levels/chapter_1/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room._save.set_stele_state(room.COMBAT_ID, MinigameStele.SteleState.UNLOCKED)
	room._combat_stele_requested(room.COMBAT_ID, MinigameStele.SteleKind.COMBAT)
	check(room.mist_enemies.size() == 3, "Mist has three persistent random opponents")
	var target := room.player as LanPlayer
	target.set_physics_process(false)
	target.position = Vector2(1800, 555)
	var progress := UnlockedProgress.new()
	target.add_child(progress)
	target.save_progress = progress
	target.save_progress_resolved = true
	var boar := room.mist_enemies[2] as MistParryEnemy
	for enemy in room.mist_enemies:
		enemy.set_physics_process(false)
	boar._spawn_wait = 0.01
	boar._physics_process(0.02)
	check(boar.state == MistAmbusher.State.WARNING and boar.warning_count == 1, "Stationary player triggers random warning")
	boar._physics_process(boar.warning_duration + 0.01)
	check(boar.state == MistAmbusher.State.CHARGE, "Real map warning launches charge")
	target.start_parry(true)
	for i in range(120):
		boar._physics_process(1.0 / 60)
		await physics_frame
		if boar.state != MistAmbusher.State.CHARGE:
			break
	check(target.combat_stats.health == target.combat_stats.max_health, "Parried charge cannot damage player")
	check(boar.state == MistAmbusher.State.RECOVERY and boar.parry_count == 1, "Real map K parry stops and counts")
	boar._physics_process(MistParryEnemy.PARRY_PAUSE + 0.01)
	check(boar.state == MistAmbusher.State.HIDDEN and boar.parry_count == 1, "Parry disappears in place with count retained")
	room.queue_free()
	await process_frame
