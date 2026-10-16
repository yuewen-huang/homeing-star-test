extends SceneTree
## Real production scene, phase actions, handoff clocks and save isolation.

class TestProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	func get_item_count(item_id: StringName) -> int: return 1 if item_id == ItemCatalog.VINE_SNARE else 0

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var player: LanPlayer
var checks := 0
var failures := 0
var output := ""
var completed: Array[int] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func tick(seconds: float, speed := 1.0) -> void:
	for i in ceili(seconds * 60):
		var delta := speed / 60.0
		boss._physics_process(delta)
		boss.vfx._process(delta)
		room.mist_field._process(delta)
		if room.mist_field._fade_tween != null and room.mist_field._fade_tween.is_valid():
			room.mist_field._fade_tween.custom_step(delta)

func clear_feedback() -> void:
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	feedback.hit_stop_serial += 1
	Engine.time_scale = 1
	feedback.screen_fx.clear()
	feedback._reset_punch()
	feedback.shake_remaining = 0
	if is_instance_valid(feedback.shake_target): feedback.shake_target.offset = feedback.shake_base_offset
	feedback.clear_body_reaction(boss.animated_sprite)
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()

func capture(label: String) -> void:
	if output.is_empty(): return
	clear_feedback()
	room._process(0)
	boss.vfx._sync_body_material()
	boss.vfx.queue_redraw()
	room.mist_field.update_material()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK)

func kill_phase() -> void:
	boss.receive_skill_hit(SkillHitContext.new(&"phase_end_test", boss.combat_stats.health), player.global_position)
	clear_feedback()

func advance_handoff(label: String, next_phase: int) -> void:
	var origin := boss.position
	var player_x := player.position.x
	var old_phase := boss.phase
	var terrain_count := boss.root_phase.nodules.size()
	var support_count := player.sloped_ground_surfaces.size()
	kill_phase()
	check(boss.state == DeerBoss.State.PHASE_END and boss.invulnerable and boss.phase_transition.stage == &"fall", label+": depletion starts protected fall")
	check(boss.attack_hitbox.attack == null and not boss.clash_phase.pressure_fx.visible, label+": outstanding contact/wind is cleared")
	check(boss.root_phase.volleys.is_empty() and boss.root_phase.nodules.size() == terrain_count and player.sloped_ground_surfaces.size() == support_count, label+": temporary root attacks cancel while permanent terrain/supports survive")
	tick(0.5)
	check(String(boss.animated_sprite.animation).begins_with("death_") and boss.phase == old_phase, label+": physical falling clips keep old phase colour")
	check(is_equal_approx(player.position.x, player_x), label+": fall does not shove player")
	await capture(label+"_01_fall")
	var fall_time := boss.phase_transition.duration(DeerPhaseTransition.FALL)
	tick(fall_time - 0.5 + 0.05)
	check(String(boss.animated_sprite.animation).begins_with("getup_") and boss.phase_transition.stage == &"rise", label+": falling joins actual getup files")
	check(is_equal_approx(player.position.x, player_x), label+": getup does not shove player")
	await capture(label+"_02_getup")
	var rise_time := boss.phase_transition.duration(DeerPhaseTransition.RISE)
	tick(rise_time)
	check(boss.phase == next_phase and boss.phase_transition.stage == &"roar" and String(boss.animated_sprite.animation).begins_with("roar_"), label+": new phase is announced by roar")
	check(boss.combat_stats.health == 300 and boss.combat_stats.poise == 120 and boss.invulnerable, label+": new bars refill during protected announcement")
	check(player.boss_controlled, label+": roar owns player shove until handoff ends")
	var tint: Color = boss.vfx._body_material.get_shader_parameter("phase_color")
	check(tint.is_equal_approx(boss.phase_color()), label+": actual body shader has next phase colour")
	var before := player.position.x
	tick(0.2)
	check(is_equal_approx(absf(player.position.x - before), 18.0), label+": continuous shove advances 18 px in 200 action ms")
	before = player.position.x
	tick(0.2)
	check(is_equal_approx(absf(player.position.x - before), 18.0), label+": shove continues on subsequent frames")
	await capture(label+"_03_roar")
	boss.receive_skill_hit(SkillHitContext.new(&"protected", 300), player.global_position)
	check(boss.combat_stats.health == 300, label+": attacks cannot skip phase announcement")
	var health := player.combat_stats.health
	tick(DeerPhaseTransition.ROAR_DURATION)
	check(boss.phase == next_phase and boss.state == DeerBoss.State.IDLE and not boss.invulnerable, label+": completed roar resumes production combat")
	check(not player.boss_controlled and player.combat_stats.health == health, label+": control resumes without shove damage")
	check(boss.position.is_equal_approx(origin), label+": handoff never teleports deer to spawn")
	check(boss.root_phase.nodules.size() == terrain_count, label+": phase handoff preserves permanent root terrain")
	check(completed.back() == old_phase, label+": previous phase emits exactly one completion")
	await capture(label+"_04_ready")

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	var previous := root.get_node("SaveProgress")
	root.remove_child(previous); previous.free()
	var progress := TestProgress.new(); progress.name = "SaveProgress"; root.add_child(progress)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate() as Chapter1DeerBossRoom
	root.add_child(room); current_scene = room
	boss = room.deer; player = room.player
	boss.set_physics_process(false); player.set_physics_process(false); room.mist_field.set_process(false)
	await process_frame; await process_frame
	boss.vfx.set_process(false)
	boss.phase_completed.connect(func(phase: int) -> void: completed.append(phase))
	boss.position = Vector2(1000,555); player.position = Vector2(840,555)
	check(boss.auto_advance_phases and boss.playable_phase_count == 3 and not boss.manual_control, "Production scene enables three automatic phases")
	check(player.contextual_special_item == ItemCatalog.VINE_SNARE, "Mist keeps existing contextual snare")
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	check(feedback.prepare_hit_reaction_visual(boss.animated_sprite) == boss.animated_sprite.material, "Phase shader shares the actual common hit-reaction material")
	var expected := [Color("fff8ed"),Color("a87545"),Color("b9e7ff"),Color("78df85")]
	for phase in 4:
		boss.phase=phase+1;boss._show_clip(&"idle_ING",0);boss.vfx._process(0)
		boss.announce_phase()
		var tint: Color = boss.vfx._body_material.get_shader_parameter("phase_color")
		check(tint.is_equal_approx(expected[phase]), "Chest shader phase %d colour" % (phase+1))
		room.mist_field.modulate.a=0
		await capture("colour_%d"%(phase+1))
	boss.phase=1;boss.reset_phase();boss.position=Vector2(1000,555);player.position=Vector2(840,555)
	await advance_handoff("mist_to_root",2)
	check(player.contextual_special_item == &"mist_veil" and player.get_node("SkillBar")._context_label.text == "Q 分身", "Root stage exposes its existing decoy Q instead of the snare")
	check(not room.mist_field.is_processing() and is_zero_approx(room.mist_field.modulate.a), "Root battle has no lingering mist")
	player.position=Vector2(840,120)
	boss._choose_attack(180)
	check(boss.state in [DeerBoss.State.LIGHT,DeerBoss.State.HEAVY], "Production root AI selects its ground attacks")
	boss.start_attack(DeerBoss.State.LIGHT);tick(0.7)
	check(not boss.root_phase.nodules.is_empty(), "Production light contact grows real standable root terrain")
	await capture("root_terrain")
	boss._recover(0);boss._recovery=0;boss._phase_age=8;boss.combat_stats.set_health_ratio(0.5)
	boss._physics_process(1.0/60)
	boss._physics_process(1.0/60)
	check(boss.state==DeerBoss.State.ROOT_HUNT and boss.root_phase.active, "Production root AI starts root tide at half health")
	player.position=Vector2(840,555);tick(1.25)
	player.special_item_use_requested.emit(&"mist_veil")
	check(boss.root_phase.countered and boss.item_cooldown>0, "Production Q signal activates the existing root-tide decoy")
	tick(8.0)
	check(boss.state==DeerBoss.State.STAGGER and not boss.invulnerable and is_equal_approx(player.animated_sprite.modulate.a,1.0), "Countered root tide exposes a real punish window and restores player")
	player.position=Vector2(840,555)
	await advance_handoff("root_to_wind",3)
	check(player.contextual_special_item==&"" and player.get_node("SkillBar")._contextual_item==&"", "Wind clears stage-specific Q context")
	var seen: Dictionary={}
	var bounded:=true
	boss._rng.seed=12
	for i in 120:
		boss._choose_attack(180)
		seen[boss.clash_phase.action_id]=true
		bounded=bounded and boss.phase_ai.wind_repeat<=2
	check(seen.size()==6 and bounded, "Production wind AI uses all six real combos without three repeats")
	boss._choose_attack(700)
	check(boss.clash_phase.action_id in [&"sweep_charge",&"crossover"], "Distant wind target selects movement combo")
	boss._change_state(DeerBoss.State.IDLE);boss._recovery=0
	player.position=Vector2(500,120)
	boss._physics_process(1.0/60)
	check(boss.state in [DeerBoss.State.WALK,DeerBoss.State.CLASH], "Production wind resumes actual approach/attack loop")
	player.position=Vector2(boss.position.x-160,555)
	kill_phase();tick(1.2)
	check(boss.state==DeerBoss.State.COMPLETE and boss.phase==3 and boss.animated_sprite.animation==&"death_END", "Third phase falls and ends current three-phase encounter")
	check(completed==[1,2,3] and not player.boss_controlled, "All three completions occur once and leave player control usable")
	check(boss.root_phase.nodules.is_empty() and player.sloped_ground_surfaces.is_empty(), "Encounter defeat removes permanent terrain and supports")
	await capture("three_phase_defeated")
	room.restart_mist_phase();boss.set_physics_process(false)
	check(boss.phase==1 and boss.combat_stats.health==300 and player.combat_stats.health==100 and player.contextual_special_item==ItemCatalog.VINE_SNARE, "Retry restarts the complete encounter from mist")
	player.position=Vector2(1340,555);kill_phase();tick(1.5)
	check(player.boss_controlled, "Interrupted handoff reaches owned roar control")
	var before_slow := player.position.x
	var elapsed_slow := boss.phase_transition.elapsed
	tick(0.2, 0.25)
	check(is_equal_approx(absf(player.position.x-before_slow),4.5) and is_equal_approx(boss.phase_transition.elapsed-elapsed_slow,0.05), "Quarter speed keeps transition animation and shove on the same action clock")
	before_slow = player.position.x
	elapsed_slow = boss.phase_transition.elapsed
	boss.red_parry_hold = true
	tick(0.2)
	check(is_equal_approx(player.position.x,before_slow) and is_equal_approx(boss.phase_transition.elapsed,elapsed_slow), "Combat pause freezes both roar and shove")
	boss.red_parry_hold = false
	room.restart_mist_phase();boss.set_physics_process(false)
	check(not player.boss_controlled and boss.phase==1 and not boss.phase_transition.active, "Retry during roar releases control and cancels transition")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH)==existed and (not existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)==saved), "Production integration tests preserve original save bytes")
	clear_feedback();current_scene=null;room.free()
	var music := (root.get_node("SceneTransition") as SceneTransitionService).music_player
	music.stop(); music.stream = null
	await process_frame;await process_frame
	await create_timer(0.2,true,false,true).timeout
	print("PRODUCTION DEER: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
