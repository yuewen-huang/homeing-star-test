extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var deer: DeerDuelBoss

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path.ends_with("deer_duel_adapter.gd"): room.select_boss(i)
	await process_frame
	deer = room.adapter.boss
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	deer.set_physics_process(false)
	for side in [-1,1]:
		deer.restart_duel()
		deer.set_physics_process(false)
		deer.manual_control = true
		deer.position.x = 950 if side < 0 else 350
		room.player.position.x = 500
		deer.start_move(1,700)
		for f in 60: tick()
		check(not is_instance_valid(deer.effects._landing),"No soil impulse before touchdown, facing %d" % side)
		for f in 4: tick()
		var landing: Node2D = deer.effects._landing
		check(is_instance_valid(landing),"Touchdown spawns the real soil impulse, facing %d" % side)
		check(landing.global_position.is_equal_approx(Vector2(700,555)),"Soil impulse stays on the locked floor point")
		check(landing.pulses.size()==1 and not landing._outward_started,"Compression precedes the outward wake")
		var probes := deer.attack_probes()
		check(probes.size()==1 and probes[0].shape.size == Vector2(156,56),"Decorative ground propagation keeps the original landing footprint")
		var paused_age: float = landing.age
		deer.red_parry_hold = true
		for f in 15: tick()
		check(landing.age == paused_age,"Ground layers share the boss action pause")
		deer.red_parry_hold = false
		for f in 3: tick()
		check(landing.pulses.size()==2,"Outward soil wake fires exactly once after compression")
		check(not landing.pulses[0].spec.cracks and not landing.pulses[1].spec.wave,"No old geometric crack or luminous ring")
		for f in 45:
			if DisplayServer.get_name() != "headless" and f%2==0:
				await capture("landing_%d_%03d" % [side,f])
			tick()
		check(not is_instance_valid(deer.effects._landing) and deer.attack_probes().is_empty(),"Soil and hitbox are gone while the punish window is still open")
		check(deer.opening > 0,"Landing spectacle does not consume the guaranteed punish")
	deer.start_move(1,700)
	for f in 65: tick()
	var old_landing: Node2D = deer.effects._landing
	deer.cancel_duel()
	check(not is_instance_valid(old_landing),"Cancel removes the complete soil subtree")
	current_scene = null
	room.free()
	await process_frame
	expect_save_untouched()
	finish("DEER DUEL LANDING")

func tick() -> void:
	deer._physics_process(1.0/60)
	deer.vfx._process(1.0/60)

func capture(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
