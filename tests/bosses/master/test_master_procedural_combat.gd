extends "../../support/harness.gd"

func run() -> void:
	var progress := use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var previous_invincible := assist.player_invincible
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	check(room.player.is_invulnerable() and room.adapter.master.manual_control, "Observer remains the default")
	check(root.get_node("SaveProgress") != progress, "Production save lookup is isolated in the room")
	for move: StringName in MasterClashRhythm.ORDER:
		for facing in [-1.0, 1.0]:
			room.adapter._rebuild()
			var boss: MasterBoss = room.adapter.master
			boss.position.x = 640
			room.adapter.target.position.x = 640+facing*180
			boss.set_process(false)
			boss.attack_hitbox.set_physics_process(false)
			boss.start_clash_rhythm(move)
			var rhythm: MasterClashRhythm = boss.clash_rhythm
			var all_ribbons := true
			var all_contacts := true
			for strike: Dictionary in rhythm.strikes:
				rhythm.elapsed = float(strike.t)+0.001
				rhythm.step(rhythm.elapsed)
				all_ribbons = all_ribbons and rhythm._contact_ribbons.has(rhythm._open)
				all_contacts = all_contacts and boss.attack_collision_shape.shape is ConvexPolygonShape2D
				all_contacts = all_contacts and boss.attack_hitbox.global_transform.is_equal_approx((rhythm._contact_ribbons[rhythm._open].node as Node2D).global_transform)
				all_ribbons = all_ribbons and not boss.wind_effect.visible
				rhythm.elapsed = float(strike.close)+0.001
				rhythm.step(rhythm.elapsed)
			check(all_ribbons, "%s %s: every cut uses a live trajectory" % [move, facing])
			check(all_contacts, "%s %s: contacts follow the visible blade band" % [move, facing])
			rhythm.cancel()
			check(boss.attack_collision_shape.shape is RectangleShape2D and boss.attack_hitbox.attack == null, "Cancel restores the legacy shape for other phases")
	room.set_combat_simulation(true)
	var master: MasterBoss = room.adapter.master
	master.set_process(false)
	check(not master.manual_control and master.combat_target == room.player, "Live master targets the actual player with production AI")
	check(master.is_in_group(&"damageable") and master.get_node("Hurtbox").collision_layer != 0, "Live master accepts player hits")
	check(not assist.player_invincible and not room.player.is_invulnerable(), "Live mode disables observer and global invincibility")
	check(room.player.can_accept_parry_action(), "Live mode enables the production parry route")
	master.manual_control = true
	master.position = Vector2(640, 555)
	room.player.reset_after_map_fall(Vector2(380, 555))
	master.start_clash_rhythm(&"basic_down")
	var before_sweep: int = room.player.combat_stats.health
	for i in 100:
		master._process(1.0/120.0)
		await physics_frame
	check(room.player.combat_stats.health < before_sweep, "The visible moving blade really hits a grounded player at its cutting edge")
	master._cancel_press_return()
	room.player.reset_after_map_fall(Vector2(380, 555))
	var qi := MasterSwordQi.new()
	room.add_child(qi)
	qi.launch(master, Vector2(600, 300), Vector2(300, 300), CombatAttackData.new(&"live_qi", master, 5, 0, 0, 0))
	check(qi.visual.samples.size() > 20 and qi.hitbox.get_child_count() == 12, "Flying crescent is formed at release and uses twelve curved collision sections")
	qi.free()
	var attack := CombatAttackData.new(&"live_room_damage_check", master, 7, 0, 0.0, 0.0)
	var health: int = room.player.combat_stats.health
	room.player.receive_combat_hit(attack)
	check(room.player.combat_stats.health == health-7, "Production player receives real combat damage")
	room.reset_room()
	check(room.combat_simulation and room.player.combat_stats.health == room.player.combat_stats.max_health, "R retries live combat at full health")
	room.set_combat_simulation(false)
	check(room.player.is_invulnerable() and room.adapter.master.manual_control, "Switch off restores safe observation")
	check(assist.player_invincible == previous_invincible, "Switch off restores previous practice setting")
	room.free()
	current_scene = null
	await process_frame
	await process_frame
	check(root.get_node("SaveProgress") == progress, "Leaving restores the original save service")
	expect_save_untouched()
	finish("MASTER PROCEDURAL COMBAT")
