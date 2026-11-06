extends "../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var original_speed := Engine.time_scale
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as BossDevelopmentRoom
	root.add_child(room)
	current_scene=room
	await wait_frames(3)
	check(room.adapter.deer is DeerDuelBoss and room.selected_boss==0,"Development room defaults to the shipped deer repertoire")
	check(room.boss_picker.item_count==BossDevelopmentRoom.BOSS_CATALOG.size(),"Selector exposes exactly the current catalog")
	check(BossDevelopmentRoom.BOSS_CATALOG.all(func(item): return not item.name.contains("已弃用")),"Retired slice entries are absent")
	check(room.player.is_invulnerable() and not room.player.can_accept_parry_action(),"Manual observer is safe and does not intercept parries")
	room.play_action(0)
	check(room.adapter.deer.move==&"rush","Manual button starts the production first-phase rush")
	await wait_frames(90)
	check(room.player.combat_stats.health==100,"Manual preview cannot damage the observer")
	var phase_count := 0
	for i in BossDevelopmentRoom.BOSS_CATALOG.size():
		var path: String=BossDevelopmentRoom.BOSS_CATALOG[i].adapter.resource_path
		if not (path.ends_with("deer_duel_adapter.gd") or path.ends_with("deer_root_duel_adapter.gd") or path.ends_with("deer_vine_pursuit_adapter.gd") or path.ends_with("deer_wind_duel_adapter.gd")): continue
		phase_count+=1
		room.select_boss(i)
		await wait_frames(3)
		check(room.adapter.deer.manual_control,"Each current phase starts with AI disabled")
		room.set_combat_simulation(true)
		await wait_frames(2)
		check(not room.adapter.deer.manual_control and not room.player.is_invulnerable(),"Each current phase can enter actual shared combat")
		room.set_combat_simulation(false)
		await wait_frames(2)
	check(phase_count==4,"All four shipped phases retain isolated development entries")
	var listeners := room.player.combat_stats.health_depleted.get_connections()
	check(listeners.size()==1,"Switching phases leaves only the current actor's defeat listener")
	room.select_boss(1)
	await wait_frames(3)
	check(room.adapter.boss is MasterBoss,"Other boss adapters remain available")
	room.set_playback_speed(0)
	check(is_equal_approx(Engine.time_scale,.25),"Preview speed selector remains usable")
	current_scene=null
	room.free()
	await wait_frames(2)
	check(is_equal_approx(Engine.time_scale,original_speed),"Leaving development restores playback speed")
	expect_save_untouched()
	finish("BOSS DEVELOPMENT ROOM")
