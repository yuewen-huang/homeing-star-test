extends SceneTree

class UnlockedProgress extends SaveProgressService:
	func _ready() -> void:
		pass
	func is_ability_unlocked(_ability_id: StringName) -> bool:
		return true

var failures := 0
func _initialize() -> void:
	call_deferred("run_tests")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run_tests() -> void:
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_level(BattleAssistSettingsService.Level.STRONG)
	for key in [KEY_X, KEY_A, KEY_J, KEY_L, KEY_K, KEY_NONE]:
		var room = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
		root.add_child(room)
		room.set_process(false)
		current_scene = room
		var player := room.get_node("Lan") as LanPlayer
		var boss = room.get_node("MasterBoss")
		var progress := UnlockedProgress.new()
		player.add_child(progress)
		player.save_progress = progress
		player.save_progress_resolved = true
		player.set_physics_process(false)
		boss.set_process(false)
		boss.set_physics_process(false)
		boss.combat_timeline.set_process(false)
		boss.combat_timeline.set_physics_process(false)
		player.position = Vector2(0,555)
		boss.position = Vector2(100,555)
		boss.combat_timeline.play(&"attack_1")
		boss.combat_timeline.seek(0.0, true)
		boss.state = boss.State.ATTACK
		boss.attack_hitbox.global_position = player.global_position + Vector2(0,-29)
		boss.attack_collision_shape.position = Vector2.ZERO
		boss.attack_collision_shape.shape.size = Vector2(60,60)
		var attack := CombatAttackData.new(&"shared_qte_test", boss, 10, 10, 0.0, 0.0)
		boss._start_contact_parry_prompt(1,attack)
		check(boss.contact_parry_active and boss.contact_qte.active, "Boss did not use shared QTE")
		check(is_equal_approx(boss.contact_qte.progress.size.y, 7.0), "QTE timer lost original thin-bar height")
		if key == KEY_K and OS.get_cmdline_user_args().size() == 2:
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var output := OS.get_cmdline_user_args()[1]
			DirAccess.make_dir_recursive_absolute(output)
			root.get_texture().get_image().save_png(output.path_join("boss_qte.png"))
		if key == KEY_NONE:
			boss.contact_qte.tick(1.1)
		else:
			var event := InputEventKey.new()
			event.keycode = key
			event.physical_keycode = key
			event.pressed = true
			root.push_input(event)
		check(not boss.contact_parry_active and not boss.parry_assist_prompt.visible, "Boss QTE did not close immediately")
		check(is_equal_approx(boss.combat_timeline.speed_scale,1.0), "Boss speed not restored")
		if key == KEY_L:
			player.start_back_dodge(-1)
		for i in range(6):
			await physics_frame
		if key in [KEY_K,KEY_L]:
			check(player.combat_stats.health == player.combat_stats.max_health, "Boss K parry / L roll took damage")
		else:
			check(player.combat_stats.health == player.combat_stats.max_health-10, "Boss wrong key / timeout failed ordinary single-hit damage")
		room.queue_free()
		await process_frame
		Engine.time_scale = 1.0

	var manager := root.get_node("ParryQTE") as ContactParryQTE
	var persistent_id := manager.get_instance_id()
	for scenario in ["locked", "scene_change", "owner_exit", "target_exit", "arbitration"]:
		var room = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
		root.add_child(room)
		room.set_process(false)
		current_scene = room
		var player := room.get_node("Lan") as LanPlayer
		var boss = room.get_node("MasterBoss")
		var story := SaveProgressService.new()
		story._loaded = true
		# A fresh in-memory service tests real story facts, without entering the tree / loading saves.
		player.save_progress = story
		player.save_progress_resolved = true
		player.set_physics_process(false)
		boss.set_process(false)
		boss.set_physics_process(false)
		boss.combat_timeline.set_process(false)
		boss.combat_timeline.set_physics_process(false)
		boss.state = boss.State.ATTACK
		var attack := CombatAttackData.new(&"lifecycle", boss,10,10,0.0,0.0)
		if scenario == "locked":
			check(player.is_ability_locked(SaveProgressService.ABILITY_PARRY), "Fresh story K must be locked")
			boss._start_contact_parry_prompt(1,attack)
			check(not manager.active and not manager.panel.visible and not boss.contact_parry_active, "Boss bypassed locked K")
		else:
			var unlocked := UnlockedProgress.new()
			player.add_child(unlocked)
			player.save_progress = unlocked
			boss._start_contact_parry_prompt(1,attack)
			check(manager.is_owner(boss), "Global manager did not accept Boss")
			if scenario == "scene_change":
				current_scene = null
				manager.tick(0.01)
			elif scenario == "owner_exit":
				boss.queue_free()
				await process_frame
			elif scenario == "target_exit":
				player.queue_free()
				await process_frame
			else:
				var enemy := MistAmbusher.new()
				enemy.setup(player, MistAmbusher.Species.BOAR,Vector2(500,555))
				room.add_child(enemy)
				enemy.set_physics_process(false)
				enemy._begin_warning()
				enemy._begin_charge()
				enemy._begin_qte()
				check(manager.is_owner(boss) and enemy.state == MistAmbusher.State.CHARGE, "Mist overwrote Boss QTE")
				enemy._release_qte()
				check(manager.is_owner(boss), "Non-owner cancelled global QTE")
				manager.cancel(boss, true)
			check(not manager.active and not manager.panel.visible and manager.source == null and manager.target == null, "Global QTE leaked across lifecycle boundary")
		story.free()
		room.queue_free()
		await process_frame
		check(manager.get_instance_id() == persistent_id, "Manager did not persist across scene teardown")
	for node_name in ["parry_player", "impact_player"]:
		(root.get_node("CombatFeedback").get(node_name) as AudioStreamPlayer).stop()
	(root.get_node("SceneTransition").get("music_player") as AudioStreamPlayer).stop()
	for i in range(4):
		await process_frame
	if failures == 0:
		print("PASS: global persistent QTE; locked K, scene/owner/target cleanup and Boss/mist arbitration; X/A/J close immediately and deal one hit; K parry, L evade, timeout and speed restoration")
	quit(1 if failures else 0)
