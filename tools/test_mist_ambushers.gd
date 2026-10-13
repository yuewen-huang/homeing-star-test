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
	player = load("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
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
			(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.NONE)
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
			(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)
			enemy = spawn_enemy(kind, direction * 25.0)
			prepare_charge(enemy)
			enemy._physics_process(0.016)
			check(enemy.state == MistAmbusher.State.QTE and enemy.qte_panel.visible and not enemy.attack_hitbox.monitoring, "Contact QTE did not intercept hit")
			enemy.resolve_qte_success()
			await settle()
			check(player.combat_stats.health == player.combat_stats.max_health and enemy.state == MistAmbusher.State.RECOVERY and not enemy.qte_panel.visible, "QTE success did not parry safely")

			await new_arena()
			enemy = spawn_enemy(kind, direction * 25.0)
			prepare_charge(enemy)
			enemy._physics_process(0.016)
			enemy.contact_qte.tick(1.1)
			await settle()
			check(player.combat_stats.health < player.combat_stats.max_health, "QTE timeout did not resume collision")

			await new_arena()
			enemy = spawn_enemy(kind, direction * 25.0)
			prepare_charge(enemy)
			enemy._physics_process(0.016)
			player.non_parry_action_requested.emit()
			player.start_back_dodge(-direction)
			await settle()
			check(player.combat_stats.health == player.combat_stats.max_health and not enemy.qte_panel.visible, "Roll during QTE failed to evade")

		# Real viewport input covers keys absent from the player's action signal.
		for key in [KEY_X, KEY_A, KEY_J, KEY_L, KEY_K]:
			await new_arena()
			enemy = spawn_enemy(kind, 25.0)
			prepare_charge(enemy)
			enemy._physics_process(0.016)
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.keycode = key
			event.pressed = false
			root.push_input(event)
			check(enemy.state == MistAmbusher.State.QTE, "Key release incorrectly cancelled QTE")
			event.pressed = true
			event.echo = true
			root.push_input(event)
			check(enemy.state == MistAmbusher.State.QTE, "Held-key echo incorrectly cancelled QTE")
			event.echo = false
			root.push_input(event)
			check(not enemy.qte_panel.visible and not enemy.contact_qte.active, "Pressed key did not immediately close QTE")
			if key == KEY_L:
				player.start_back_dodge(-1.0)
			await settle()
			if key in [KEY_K, KEY_L]:
				check(player.combat_stats.health == player.combat_stats.max_health, "K parry / L roll took damage")
			else:
				check(player.combat_stats.health == player.combat_stats.max_health - enemy.attack_data.health_damage, "Wrong key did not settle exactly one normal hit")

		await new_arena()
		enemy = spawn_enemy(kind)
		prepare_charge(enemy)
		enemy._physics_process(0.016)
		enemy.receive_hit(enemy.health, player.global_position)
		await settle()
		check(enemy.state == MistAmbusher.State.DEAD and not enemy.attack_hitbox.monitoring and not enemy.contact_qte.active, "Death did not cancel attack/QTE")

	# Reproduce movement held BEFORE contact: no fresh direction-key event occurs in QTE.
	for kind in [MistAmbusher.Species.BOAR, MistAmbusher.Species.RAT, MistAmbusher.Species.BEE]:
		for direction in [-1.0, 1.0]:
			for outcome in ["timeout", "K", "X", "external"]:
				await new_arena()
				var action := &"ui_left" if direction < 0 else &"ui_right"
				Input.action_press(action)
				player.input_direction = direction
				player.latest_pressed_direction = direction
				player.play_run()
				player.set_physics_process(true)
				var running_start := player.position
				for i in range(4):
					await physics_frame
				check(absf(player.position.x - running_start.x) > 1.0, "Held direction did not reproduce real running")
				var running_enemy := spawn_enemy(kind, direction * 25.0)
				prepare_charge(running_enemy)
				running_enemy._physics_process(0.016)
				check(running_enemy.state == MistAmbusher.State.QTE and player.contact_qte_paused, "Running contact did not pause Lan")
				var held_position := player.position
				var held_frame := player.animated_sprite.frame
				for i in range(12):
					await physics_frame
				check(player.position.is_equal_approx(held_position) and player.animated_sprite.frame == held_frame, "Held direction escaped QTE / animation kept advancing")
				check(running_enemy.contact_qte.active, "Holding the existing direction wrongly dismissed QTE")
				if outcome == "timeout":
					running_enemy.contact_qte.tick(1.1)
				elif outcome == "external":
					player.position.x += 1000.0
					running_enemy.contact_qte.tick(0.016)
				else:
					var event := InputEventKey.new()
					event.physical_keycode = KEY_K if outcome == "K" else KEY_X
					event.keycode = event.physical_keycode
					event.pressed = true
					root.push_input(event)
				check(not running_enemy.contact_qte.active and not player.contact_qte_paused and running_enemy.state != MistAmbusher.State.QTE and running_enemy.animated_sprite.is_playing(), "QTE exit left Lan / enemy paused")
				await settle()
				if outcome in ["timeout", "X"]:
					check(player.combat_stats.health < player.combat_stats.max_health, "Running QTE failure did not restore ordinary damage")
				elif outcome == "K":
					check(player.combat_stats.health == player.combat_stats.max_health, "Running QTE K failed parry")
				Input.action_release(action)

	for kind in [MistAmbusher.Species.BOAR, MistAmbusher.Species.RAT, MistAmbusher.Species.BEE]:
		await new_arena()
		var story := StoryProgress.new()
		player.add_child(story)
		player.save_progress = story
		check(player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Fresh story unexpectedly unlocks K")
		var locked_enemy := spawn_enemy(kind,25.0)
		prepare_charge(locked_enemy)
		locked_enemy._physics_process(0.016)
		check(locked_enemy.state == MistAmbusher.State.CHARGE and not locked_enemy.contact_qte.active and not locked_enemy.qte_panel.visible, "Locked K opened mist QTE")
		locked_enemy._begin_qte()
		check(not locked_enemy.contact_qte.active, "Direct request bypassed locked K")
		await settle()
		check(player.combat_stats.health < player.combat_stats.max_health, "Locked K suppressed ordinary damage")
		story._config.set_value(SaveProgressService.PROGRESS_SECTION, String(SaveProgressService.STORY_MASTER_PARRY_LEARNED), true)
		player.finish_hit_reaction()
		check(not player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Story milestone did not unlock K")
		locked_enemy._begin_warning()
		locked_enemy._begin_charge()
		locked_enemy._begin_qte()
		check(locked_enemy.contact_qte.is_owner(locked_enemy), "Story unlock did not enable QTE")
		locked_enemy._begin_recovery()

	await new_arena()
	var first := spawn_enemy(MistAmbusher.Species.BOAR,25.0)
	var second := spawn_enemy(MistAmbusher.Species.RAT,-25.0)
	prepare_charge(first)
	prepare_charge(second)
	first._physics_process(0.016)
	second._physics_process(0.016)
	await settle()
	check(first.state == MistAmbusher.State.QTE and second.state == MistAmbusher.State.CHARGE and not second.contact_qte.is_owner(second) and player.combat_stats.health == player.combat_stats.max_health, "Overlapping QTEs or damage behind another prompt")
	first.resolve_qte_success()
	await settle()
	arena.queue_free()
	await process_frame
	await test_full_room_ambush()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)
	Engine.time_scale = 1.0
	for i in range(10):
		await physics_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	(root.get_node("CombatFeedback") as CombatFeedbackService).impact_player.stop()
	await process_frame
	if failures == 0:
		print("PASS: held running / frozen position and animation / K, wrong key, timeout and external displacement release both actors; three species / both directions; concealment, 400px audio warning, committed attack, rearm, one hit, manual defense, roll, QTE success/timeout/roll, death and prompt arbitration")
	quit(1 if failures else 0)



func capture_gameplay() -> void:
	var output := OS.get_cmdline_user_args()[-1]
	var room = load("res://scenes/sideview/chapter_1_mist_room.tscn").instantiate()
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
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)
	for sample in ["hidden", "boar", "boar_qte", "rat", "bee", "bee_qte"]:
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
			enemy.position = target.position + Vector2(25.0 if sample.ends_with("qte") else 70.0, -22.0 if index == 2 else 0.0)
			enemy._begin_warning()
			enemy._begin_charge()
			if sample.ends_with("qte"):
				enemy._physics_process(0.016)
				check(enemy.state == MistAmbusher.State.QTE, "Rendered contact must show QTE")
			else:
				enemy.attack_hitbox.deactivate()
				enemy.animated_sprite.pause()
				enemy.animated_sprite.frame = 2
			enemy._update_visibility()
		for i in range(5):
			await process_frame
		if sample.ends_with("qte"):
			enemy.contact_qte._update_prompt()
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(output.path_join(sample + ".png"))
		check(result == OK, "Gameplay capture failed")
		print("Captured mist gameplay: ", sample)
	room.queue_free()
	await process_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	quit(1 if failures else 0)

func test_full_room_ambush() -> void:
	var room = load("res://scenes/sideview/chapter_1_mist_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
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
	for i in range(120):
		boar._physics_process(1.0 / 60)
		if boar.state == MistAmbusher.State.QTE:
			break
	check(boar.state == MistAmbusher.State.QTE and boar.qte_panel.visible, "Real charge offers contact QTE")
	check(target.combat_stats.health == target.combat_stats.max_health, "Charge cannot damage player before QTE")
	boar.resolve_qte_success()
	check(boar.state == MistAmbusher.State.RECOVERY and boar.parry_count == 1, "Real map K parry stops and counts")
	boar._physics_process(MistParryEnemy.PARRY_PAUSE + 0.01)
	check(boar.state == MistAmbusher.State.HIDDEN and boar.parry_count == 1, "Parry disappears in place with count retained")
	room.queue_free()
	await process_frame
