extends "../../support/harness.gd"

const SAMPLE := preload("res://scripts/dev/master_chop_sample.gd")
var results: Array[int] = []

func run() -> void:
	use_memory_progress()
	var baseline := JSON.stringify(MasterActionLibrary.new().data.moves)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var master: MasterBoss = room.get_node("MasterBoss")
	var lan: LanPlayer = room.get_node("Lan")
	master.set_process(false)
	lan.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	SAMPLE.install(master)
	master.phase_1_ai = SAMPLE.new()
	master.attack_hitbox.hit_resolved.connect(func(_target: Node, result: CombatHitResult.Type) -> void:
		results.append(result)
		if master.phase_1_action != null and master.phase_1_action.id == &"rise_unbalance": print("WIND HIT t=", master.phase_1_action.elapsed, " cut=", master.phase_1_action._open))
	for direction in [-1.0, 1.0]:
		for parry in [false, true]:
			master.position = Vector2(0, 555)
			master.movement_direction = direction
			master.combat_stats.restore_poise()
			lan.reset_after_map_fall(Vector2(direction * 132, 555))
			lan.combat_stats.restore_health()
			lan.parry_chain.cancel()
			results.clear()
			await physics_frame
			master.start_phase_1_action(&"vertical")
			var action := master.phase_1_action
			var timeline := action.timeline
			check(timeline.errors.is_empty() and timeline.warnings.is_empty(), "Measured chop timeline is valid")
			if parry:
				lan.start_parry(true)
				lan.animated_sprite.pause()
			var frames: Array[int] = []
			var safe := true
			var planted := true
			var ticks := 0
			while master.phase_1_action != null and ticks < 600:
				lan.combat_clock += 1.0 / 120.0
				var before := action.elapsed
				master._process(1.0 / 120.0)
				if not frames.has(master.animated_sprite.frame): frames.append(master.animated_sprite.frame)
				planted = planted and master.position == Vector2(0, 555)
				# A step straddling swing end still sweeps its final live fraction.
				if action.elapsed < 0.62 or before > 0.82:
					safe = safe and master.attack_hitbox.attack == null
				ticks += 1
			check(ticks < 600 and results == [CombatHitResult.Type.PARRY_SUCCESS if parry else CombatHitResult.Type.NORMAL_HIT], "One real contact per chop, both facings; manual parry works")
			check(planted and safe, "Feet remain planted; preparation and recovery cannot hit")
			var all_frames := true
			for frame in 16: all_frames = all_frames and frames.has(frame)
			check(all_frames, "All sixteen authored lift, swing, follow and recovery frames play")
			check(master.recovery_remaining >= 0.17, "Recovery retains the remaining tutorial punish window")
			lan.finish_defense()
			await process_frame
	for direction in [-1.0, 1.0]:
		master.position = Vector2(0, 555)
		master.movement_direction = direction
		master.combat_stats.restore_poise()
		lan.reset_after_map_fall(Vector2(direction * 132, 555))
		lan.combat_stats.restore_health()
		results.clear()
		await physics_frame
		master.start_phase_1_action(&"combo_three")
		var action := master.phase_1_action
		check(action.timeline.errors.is_empty() and action.timeline.warnings.is_empty(), "Three-chop timeline retains measured sword frames and legal contact gaps")
		var impacts := 0
		var ticks := 0
		while master.phase_1_action != null and ticks < 1000:
			lan.combat_clock += 1.0 / 120.0
			master._process(1.0 / 120.0)
			impacts = maxi(impacts, action._ground_impacts.size())
			ticks += 1
		check(ticks < 1000 and results.size() == 3, "Three chops resolve three real contacts")
		check(impacts == 3 and master.position == Vector2(0, 555), "Every chop has one cosmetic quake; no forward slide")
		await process_frame
	for direction in [-1.0, 1.0]:
		for distance in [132.0, 420.0]:
			for parry in [false, true]:
				master._cancel_phase_1_action()
				master.position = Vector2(0, 555)
				master.movement_direction = direction
				master.combat_stats.restore_poise()
				lan.reset_after_map_fall(Vector2(direction * distance, 555))
				lan.combat_stats.restore_health()
				lan.parry_chain.cancel()
				results.clear()
				await physics_frame
				master.start_phase_1_action(&"rise_unbalance")
				var action := master.phase_1_action
				check(action.timeline.errors.is_empty() and action.timeline.warnings.is_empty(), "Sweep/uppercut uses valid measured poses")
				if parry:
					lan.start_parry(true)
					lan.animated_sprite.pause()
				var wind: MasterTornado
				var defended := 0
				for tick in 600:
					if parry and results.size() > defended:
						defended = results.size()
						lan.finish_defense()
						lan.start_parry(true)
						lan.animated_sprite.pause()
					lan.combat_clock += 1.0 / 120.0
					if is_instance_valid(wind) and wind.active and wind.get_parent() == master:
						wind.set_process(false)
						wind._process(1.0 / 120.0)
					if master.phase_1_action != null:
						master._process(1.0 / 120.0)
					else:
						master.parry_pause_remaining = maxf(0.0, master.parry_pause_remaining - 1.0 / 120.0)
					if master.phase_1_action != null and is_instance_valid(master.phase_1_action.sword_qi):
						wind = master.phase_1_action.sword_qi as MasterTornado
				check(is_instance_valid(wind) and not wind.active, "Committed wind finishes after release")
				print("WIND placement=", direction, "/", distance, " parry=", parry, " results=", results)
				check(results.size() == (3 if distance < 200.0 else 1), "Near target can take two sword contacts and one delayed wind; distant target one wind contact")
				if parry: check(results.all(func(r: int) -> bool: return r == CombatHitResult.Type.PARRY_SUCCESS), "Manual guard handles sword and remote wind")
				lan.finish_defense()
				await process_frame
	room.free()
	current_scene = null
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(4)
	dev.play_action(0)
	var specimen: MasterBoss = dev.adapter.master
	specimen.set_process(false)
	specimen.phase_1_action.advance(0.75)
	var ribbon: MasterBladeTrail = specimen.phase_1_action._ribbons[0]
	check(ribbon.weight == 0.0 and not ribbon.echo and ribbon.shader_material.shader == MasterPhase1Palette.BRUSH, "Sample uses the brush material without rings or echoes")
	for i in 2:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	specimen.phase_1_action.advance(0.17)
	var quake = specimen.phase_1_action._ground_impacts[0]
	check(quake is MasterChopEarth and quake.style == "chop_earth", "Single chop uses its dedicated grounded earth study")
	check(ribbon.palette == MasterPhase1Palette.inks(), "Blade uses the original editor steel-blue palette")
	var age: float = quake.age
	specimen.parry_pause_remaining = 0.1
	specimen._process(0.02)
	check(is_equal_approx(quake.age, age), "Hit-stop freezes ground effect on the body clock")
	for i in 2:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	specimen.parry_pause_remaining = 0.0
	specimen.phase_1_action.advance(2.0)
	check(is_instance_valid(quake) and quake.get_parent() == specimen, "Ground effect retains its full decay after body recovery")
	quake.set_process(false)
	quake.advance(quake.life)
	check(quake.is_done(), "Original template has a finite tail")
	dev.play_action(1)
	check(dev.adapter.master.phase_1_action.timeline.cuts.size() == 3, "Second preview button starts three downward chops")
	var triple_action = dev.adapter.master.phase_1_action
	var previous_width := 0.0
	for i in 3:
		var contact: float = triple_action.timeline.cuts[i].release + triple_action.timeline.cuts[i].swing
		triple_action.advance(contact + 0.08 - triple_action.elapsed)
		var earth = triple_action._ground_impacts[i]
		check(earth is MasterChopEarth and earth.scale.x > previous_width, "Each triple contact uses grounded earth with increasing spread")
		previous_width = earth.scale.x
	dev.play_action(2)
	var wind_master: MasterBoss = dev.adapter.master
	wind_master.set_process(false)
	wind_master.phase_1_action.advance(1.9)
	var wind_preview := wind_master.phase_1_action.sword_qi as MasterTornado
	check(wind_preview != null and wind_preview.effect.age > 0, "Third preview button releases the wind")
	var wind_age: float = wind_preview.effect.age
	wind_master.parry_pause_remaining = 0.1
	wind_master._process(0.02)
	check(is_equal_approx(wind_preview.effect.age, wind_age), "Wind freezes with the shared parry pause")
	for i in 2:
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	dev.reset_room()
	await process_frame
	check(dev.specimen.get_child_count() == 2, "Retry removes old chop and effects")
	dev.select_combo(3)
	dev.play_action(0)
	check(dev.adapter.master.phase_1_action.timeline.cuts.size() == 3, "Accepted three-cut sample remains selectable")
	dev.select_combo(2)
	check(JSON.stringify(dev.adapter.master.action_library.data.moves) == baseline, "Leaving sample restores production moves")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER CHOP SAMPLE")
