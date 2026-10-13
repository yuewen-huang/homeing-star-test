extends SceneTree
var room
var deer: DeerBoss
var roots: DeerRootPhase
var output := ""
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("OK " if value else "FAIL ",label)
func tick(count: int,speed := 1.0) -> void:
	for i in count:
		deer._physics_process(speed/60)
		room._physics_process(speed/60)
		deer.vfx._process(speed/60)
func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func slash() -> void:
	var effect = LanPlayer.LAN_ATTACK_EFFECT_SCENE.instantiate()
	effect.setup(room.player,1.0,LanAttackEffectCatalog.attack_1x(),true)
	room.player.add_child(effect); effect.set_physics_process(false)
	for frame in 16:
		effect.set_timeline_frame(frame)
		await physics_frame; await physics_frame
		effect._physics_process(1.0/60)
	effect.free()
func run() -> void:
	(get_root().get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	deer = room.adapter.deer; roots = deer.root_phase
	deer.set_physics_process(false); deer.vfx.set_process(false); room.player.set_physics_process(false); room.set_physics_process(false)
	var health: int = room.player.combat_stats.health
	var real_player := load("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
	real_player.save_progress = room.player.save_progress; real_player.save_progress_resolved = true
	real_player.world_min_x = 32; real_player.world_max_x = 1248
	real_player.position = Vector2(380,555); room.add_child(real_player); real_player.set_physics_process(false)
	var actual_health := real_player.combat_stats.health
	real_player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	var launch_attack := CombatAttackData.new(&"deer_root_launch_test",deer,0,0,0,-430,CombatAttackData.DangerType.UNPARRYABLE_DANGER)
	check(real_player.receive_combat_hit(launch_attack) == CombatHitResult.Type.NORMAL_HIT and real_player.velocity.y == -430 and real_player.combat_stats.health == actual_health,"Real player's early failed parry does not turn a zero-damage root launch into HP loss")
	real_player.free()
	var selector := DeerRootArt.new(); selector.rng.seed = 417
	for kind in ["short","medium","high"]:
		var values: Array[String] = []
		for i in 30: values.append(selector.choose(kind))
		var complete := true; var repeats := false
		for i in 30:
			if i > 0 and values[i] == values[i-1]: repeats = true
		for i in range(0,30,3):
			var trio := {values[i]:true,values[i+1]:true,values[i+2]:true}
			if trio.size() != 3: complete = false
		check(complete and not repeats,kind+": every bag uses all 3 authored variants and has no adjacent repeat")
	check(DeerRootArt.data().clips.size() == 10,"All 9 root variants and the nodule are imported")
	room.select_combo(1); roots.art.rng.seed = 14
	check(deer.phase == 2 and not room.charge_button.visible and room.ultimate_button.text.contains("根潮"),"Root phase picker updates actions and removes charge")
	room.play_action(3)
	check(deer.state != DeerBoss.State.CHARGE,"Key 4 cannot start a root-phase rush")
	room.play_action(0); tick(34)
	check(roots.nodules.is_empty(),"Nodule does not spawn before the actual light contact")
	tick(25)
	check(roots.nodules.size() == 1 and deer.vfx._painted.is_empty(),"Actual F07 creates the authored nodule without mist impact art")
	var nodule := roots.nodules[0]
	check(nodule.health == 16 and nodule.sprite.texture is AtlasTexture,"Nodule starts at 16 HP with painted growth frames")
	await snapshot("01_nodule")
	tick(700)
	check(is_instance_valid(nodule) and not nodule.broken and nodule.sprite.texture.region == DeerRootArt.atlas("nodule",2).region,"Nodule holds the last growth frame beyond the old 6-second lifetime")
	check(nodule.support_registered and not room.player.sloped_ground_surfaces.is_empty(),"Nodule registers standable slopes after growth")
	var prior := nodule.age; deer.red_parry_hold = true; tick(12)
	check(is_equal_approx(prior,nodule.age),"Combat pause also pauses roots and persistent nodule animation")
	deer.red_parry_hold = false; tick(12,0.25)
	check(is_equal_approx(nodule.age-prior,0.05),"Quarter-speed root clock advances 50 ms in 12 ticks")
	for x in [200,350,500,1000]: roots.add_nodule(Vector2(x,555))
	tick(24)
	check(roots.nodules.size() == 5,"Permanent nodules are not removed by the former three-nodule cap")
	var damaged := roots.nodules[1]; damaged.receive_hit(1,Vector2.ZERO)
	check(roots.add_nodule(damaged.global_position+Vector2(10,0)) == damaged and damaged.health == 8,"Same-position spawn merges without healing a partly broken nodule")
	room.select_combo(0)
	check(roots.nodules.size() == 5 and room.charge_button.visible,"Nodules persist across phase selection; mist rush remains available")
	room.select_combo(1); roots.reset_all()
	check(room.player.sloped_ground_surfaces.is_empty(),"Reset removes every registered nodule slope")
	# Use the real ordinary slash collision and hit-target table, not direct receive_hit calls.
	room.player.position = Vector2(380,555); room.player.facing_direction = 1; room.player.apply_facing_direction()
	var target := roots.add_nodule(Vector2(440,555)); tick(24)
	await slash()
	check(target.health == 8 and not target.broken,"A complete real ordinary slash hits the nodule once, leaving 8 HP")
	await slash()
	check(target.health == 0 and target.broken,"Second real ordinary slash breaks the nodule")
	check(not target.support_registered and not target.is_in_group("damageable"),"Broken nodule immediately removes support and its attack target")
	await snapshot("02_nodule_broken")
	tick(22); roots.reset_all()
	# One entry, one probability roll; guarantee success/failure only within this test.
	room.player.position = Vector2(250,555); room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED; room.player.locomotion_state = LanPlayer.LocomotionState.IDLE
	var trap := roots.add_nodule(Vector2(500,555)); tick(24)
	roots.nodule_trigger_chance = 1
	room.player.locomotion_state = LanPlayer.LocomotionState.IDLE; room.player.velocity.x = 100; room.player.position.x = 500; tick(1)
	check(not is_instance_valid(trap.launch),"Walking into a nodule does not trigger its running trap")
	room.player.locomotion_state = LanPlayer.LocomotionState.RUNNING; room.player.velocity.x = 270; tick(1)
	check(not is_instance_valid(trap.launch),"Starting to run while already standing inside does not count as a fresh entry")
	room.player.position.x = 250; tick(1); room.player.air_state = LanPlayer.AirState.RISING; room.player.position.x = 500; tick(1)
	check(not is_instance_valid(trap.launch),"Jumping across a nodule does not trigger its ground trap")
	room.player.position.x = 250; room.player.air_state = LanPlayer.AirState.GROUNDED; tick(1)
	roots.nodule_trigger_chance = 0
	room.player.locomotion_state = LanPlayer.LocomotionState.RUNNING; room.player.velocity.x = 270; room.player.position.x = 500; tick(1)
	check(not is_instance_valid(trap.launch),"Zero-probability entry does not grow a tree")
	roots.nodule_trigger_chance = 1; tick(6)
	check(not is_instance_valid(trap.launch),"Staying inside does not reroll every frame")
	room.player.position.x = 250; tick(1); room.player.position.x = 500; tick(6)
	check(is_instance_valid(trap.launch) and trap.launch._spikes[0].key.begins_with("medium"),"A new running entry launches a mixed-variant medium root")
	check(room.player.hit_reaction_active and room.player.velocity.y < 0 and room.player.combat_stats.health == health,"Trap visibly launches the debug player without health loss")
	check(not trap.broken and trap.health == 16,"Trigger does not consume the permanent nodule")
	await snapshot("03_nodule_launch")
	trap.receive_hit(); trap.receive_hit()
	check(trap.broken and trap.launch.cancelled,"Destroying a trap cancels its unfinished tree attack")
	room.player.reset_after_map_fall(Vector2(380,555)); roots.reset_all(); roots.nodule_trigger_chance = 0.3
	room.play_action(1); tick(89)
	check(roots.volleys.size() == 1 and roots.volleys[0]._spikes.size() == 8,"Actual heavy F18 schedules 8 ground-anchored painted roots")
	var wave := roots.volleys[0]
	var distinct := {}
	for spike in wave._spikes: distinct[spike.key] = true
	check(distinct.size() == 3,"One heavy wave includes every short-root variant")
	tick(40)
	check(room.dummy.contacts.size() == 1 and room.dummy.contacts[0].damage == 20,"Stomp and its roots cannot hit the wooden dummy twice")
	check(room.dummy.contacts[0].last_frame <= 20,"Suppressed root hits do not extend the dummy stomp contact window")
	await snapshot("04_heavy_mixed")
	deer.enter_stagger(2)
	check(roots.volleys.is_empty(),"Red counter/stagger cancels pending ground roots")
	room.play_action(4); tick(95)
	check(roots.active and roots.round_index == 1 and deer.state == DeerBoss.State.ROOT_HUNT,"Root ultimate uses its own anchored 6-round controller")
	check(roots.volleys[0]._spikes.size() == 3 and roots.volleys[0]._spikes[1].key.begins_with("medium"),"Tracking group combines short-medium-short artwork")
	check(deer.global_position == Vector2(820,555),"Root ultimate does not teleport or charge the deer")
	await snapshot("05_tracking_warning")
	tick(49)
	await snapshot("06_tracking_roots")
	tick(315)
	check(roots.round_index == 6 and is_instance_valid(roots.final_volley) and roots.final_volley.full_floor.has_area(),"Uncountered final covers the whole legal floor after 6 rounds")
	await snapshot("07_final_warning")
	tick(60)
	var high_variants := {}
	for spike in roots.final_volley._spikes: high_variants[spike.key] = true
	check(high_variants.size() == 3,"Full-field roots visibly mix all 3 high paintings")
	var final_time := roots.final_volley._time
	roots.final_volley._time = float(roots.final_volley._spikes[0].erupt_at)+0.18
	var early_height := roots.final_volley.active_rects()[0].size.y
	roots.final_volley._time = float(roots.final_volley._spikes[0].erupt_at)+0.35
	check(roots.final_volley.active_rects()[0].size.y > early_height,"Full-floor danger height grows with the actual painted cel, not a premature invisible wall")
	roots.final_volley._time = final_time

	await snapshot("08_final_mixed")
	tick(170)
	check(not roots.active and not deer.invulnerable and deer.state == DeerBoss.State.IDLE,"Uncountered root ultimate finishes without stale invulnerability")
	roots.add_nodule(Vector2(600,555)); tick(24)
	room.play_action(4)
	check(roots.nodules.size() == 1,"Starting root ultimate does not remove a permanent nodule")
	tick(450); check(room.use_preview_item(),"Late Q redirects an already-created full-field warning to the decoy")
	check(roots.countered and roots.final_volley.no_player_damage and roots.final_volley._spikes.size() == 5 and not roots.final_volley.full_floor.has_area(),"Counter composes 5 roots, removes full-field danger and cannot hurt the player")
	await snapshot("09_decoy_warning")
	tick(61); await snapshot("10_decoy_mixed")
	tick(21)
	check(deer.state == DeerBoss.State.STAGGER and deer.poise_broken and roots.ghost == null,"Root reflection enters stagger and clears decoy with no vine cage")
	check(not is_instance_valid(deer.vfx._painted_vine) and room.player.animated_sprite.modulate.a == 1,"Root counter restores player opacity and does not reuse mist cage art")
	await snapshot("11_root_stagger")
	tick(330)
	check(not deer.poise_broken and not deer.invulnerable,"Root counter's long stagger ends normally")
	room.play_action(4); tick(75); room.use_preview_item(); tick(310)
	check(is_instance_valid(roots.ghost) and room.player.animated_sprite.modulate.a == 1,"Early-Q decoy outlives the five-second player invisibility")
	room.play_action(0)
	check(roots.ghost == null and not roots.active and room.player.animated_sprite.modulate.a == 1,"Replay cancels invisibility and pending root-ultimate events")
	# Isolate each original/ mirrored variant in the actual room for visual grounding QA.
	roots.reset_all(); deer.hide(); room.player.hide(); room.dummy.hide()
	for kind in ["short","medium","high"]:
		for mirrored in [false,true]:
			roots.cancel_attacks()
			var palette := roots._new_volley("palette",0); palette.no_player_damage = true
			for i in 3: palette.add_root(200+i*400,0,0,kind+str(i+1),mirrored)
			palette._time = 0.5; palette.queue_redraw()
			await snapshot("palette_%s_%s" % [kind,"mirrored" if mirrored else "original"])
			for spike in palette._spikes:
				check(palette.art_index(spike) == 3 and palette.visible_root(spike),"Full-height authored %s stays visible in palette" % spike.key)
	deer.show(); room.player.show(); room.dummy.show()
	room.reset_room(); await process_frame; await process_frame
	deer = room.adapter.deer; roots = deer.root_phase
	deer.set_physics_process(false); deer.vfx.set_process(false)
	check(roots.nodules.is_empty() and roots.volleys.is_empty() and room.player.sloped_ground_surfaces.is_empty(),"Room reset clears all roots, collision and pending attacks")
	check(room.player.combat_stats.health == health,"Debug playthrough never changes player health")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == existed and (not existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved),"Progress and real inventory unchanged")
	current_scene = null; room.free()
	print("PAINTED ROOT PHASE: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
