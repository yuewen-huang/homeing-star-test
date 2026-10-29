extends SceneTree
class MemorySave extends SaveProgressService:
	var fail_write := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_write
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var field: Chapter2SaltField
var save: MemorySave
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",label_)
func enter() -> void:
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
func advance(seconds: float) -> void:
	for i in ceili(seconds*60): field.crab_encounter.step(1.0/60)
func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label_+".png"))
func wait_for_map_fade() -> void:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for i in 80:
		await create_timer(0.05).timeout
		if not transition.is_transitioning: return
func run() -> void:
	seed(20261018)
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	save._config.set_value("map_states","chapter_2_salt_field",{"boss_pile":1,"dug":[]})
	enter()
	field.feet = field.piles[1].ground_position+Vector2(0,42)
	field._sync_view(0)
	field.target = 1
	field._finish_dig()
	var encounter = field.crab_encounter
	var player: LanPlayer = field.pawn.player
	var crab: CrystalCrabBoss = encounter.crab
	check(encounter.active and encounter.entering and not crab.visible,"Real excavation triggers underground entrance")
	check(player.get_parent()==encounter.battle_root and player.input_frozen and not player.is_physics_processing(),"Existing Lan transferred safely from planar control")
	advance(1.8)
	check(crab.current_clip==&"burrow_END" and crab.visible and crab.source_frame>=23,"Entrance plays authored emergence only")
	check(is_equal_approx(player.position.y,crab.position.y),"Player pulled onto boss baseline")
	check(signf(crab.position.x-player.position.x)==player.facing_direction and signf(player.position.x-crab.position.x)==crab.direction,"Both actors face each other on entrance")
	check(crab.attack_hitbox.attack==null,"Entrance cannot damage Lan")
	await capture("salt_crab_emergence")
	advance(0.7)
	check(not encounter.entering and player.is_physics_processing() and not player.input_frozen and not crab.manual_control,"Entrance enables actual autonomous fight and player physics")
	check(player.hurtbox.monitorable and player.hurtbox.collision_layer==4,"Production damage receiver restored")
	player.set_physics_process(false)
	crab.set_physics_process(false)
	Input.action_press(&"jump")
	player._physics_process(1.0/60)
	Input.action_release(&"jump")
	check(player.position.y<encounter.baseline,"Real jump input leaves the explicit baseline")
	player.reset_after_map_fall(encounter.pull_to)
	Input.action_press(&"ui_down")
	player._physics_process(1.0/60)
	Input.action_release(&"ui_down")
	check(player.animated_sprite.animation==&"crouch","Production crouch restored")
	player.reset_after_map_fall(encounter.pull_to)
	crab.start_quake(&"double",player.position)
	crab._physics_process(0.45)
	await capture("salt_crab_warning")
	crab._physics_process(0.25)
	await capture("salt_crab_combat")
	crab._physics_process(1.4)
	await capture("salt_crab_recovery")
	# Death clears the old boss, preserves discovery, and re-enters after respawn.
	field._respawn_after_worm()
	await process_frame
	encounter = field.crab_encounter
	crab = encounter.crab
	check(encounter.active and encounter.entering and crab.combat_stats.health==crab.combat_stats.max_health,"Death retries with a fresh boss and intact discovery")
	advance(2.5)
	player.set_physics_process(false)
	crab.set_physics_process(false)
	save.fail_write = true
	player.reset_after_map_fall(crab.position+Vector2(150,0))
	crab.combat_stats.health = 1
	player.perform_special_attack(-1,1.0)
	var killing_effect: Node = player.timeline_attack_effect
	player.animated_sprite.pause()
	killing_effect.set_timeline_frame(10)
	await physics_frame
	await physics_frame
	await process_frame
	check(crab.combat_stats.health==0,"Real special attack hitbox kills crab")
	check(not is_instance_valid(killing_effect) or killing_effect.is_queued_for_deletion() or killing_effect.detached_from_source,"Victory does not leave an attached undriven special effect")
	check(crab.peaceful and not encounter.active and encounter.pending_victory,"Defeat pacifies immediately even if persistence fails")
	check(player.get_parent()==field.pawn and not player.is_physics_processing() and not player.hurtbox.monitorable,"Victory returns to planar exploration")
	check(crab.attack_hitbox.attack==null and not crab.is_in_group("damageable"),"Peaceful crab has no attacks and is not targetable")
	var start := crab.position
	crab.set_physics_process(true)
	advance(4)
	check(crab.position.distance_to(start)>10 and crab.rhythm==null,"Defeated crab wanders without attacking")
	check(not save.has_completed(encounter.VICTORY),"Failed save does not claim persistent completion")
	save.fail_write = false
	advance(1.1)
	check(save.has_completed(encounter.VICTORY) and not encounter.pending_victory,"Victory save retries successfully")
	await capture("salt_crab_peaceful")
	field.free()
	current_scene = null
	enter()
	check(field.crab_encounter.crab.peaceful and not field.crab_encounter.active,"Reentry restores peaceful crab without entrance or refight")
	var resident: CrystalCrabBoss = field.crab_encounter.crab
	resident.start_action(&"walk",resident.position+Vector2(100,0))
	resident.receive_hit(99,resident.position)
	check(resident.combat_stats.health==resident.combat_stats.max_health and resident.invulnerable,"Reentered resident stays invulnerable while walking")
	field.free()
	current_scene = null
	save._config.set_value("progress","chapter_2_salt_crab_defeated",false)
	enter()
	await process_frame
	advance(2.5)
	encounter = field.crab_encounter
	crab = encounter.crab
	player = field.pawn.player
	player.set_physics_process(false)
	crab.set_physics_process(false)
	player.reset_after_map_fall(crab.position+Vector2(150,0))
	crab.combat_stats.health = 1
	player.perform_special_attack(-1,1.0,crab)
	var max_effect: Node = player.timeline_attack_effect
	player.animated_sprite.pause()
	max_effect.set_timeline_frame(10)
	await physics_frame
	await physics_frame
	await process_frame
	check(crab.combat_stats.health==0 and not encounter.active,"Real enhanced special attack hitbox finishes encounter")
	check(not is_instance_valid(max_effect) or max_effect.is_queued_for_deletion() or max_effect.detached_from_source,"Enhanced wolf effect cannot freeze on Lan after victory")
	await create_timer(0.4).timeout
	check(not is_instance_valid(max_effect) and player.active_attack_effects.is_empty(),"Victory releases the killing effect and its tracking references")
	await capture("salt_crab_special_kill_clean")
	field.free()
	current_scene = null
	await process_frame
	check(not paused,"Leaving a battle-triggered departure restores the tree pause state")
	# Old victories opt in at the peaceful crab; the shared dialogue/comic own input.
	save._config = ConfigFile.new()
	save._config.set_value("map_states","chapter_2_salt_field",{"boss_pile":1,"dug":[1]})
	save._config.set_value("progress","chapter_2_salt_crab_defeated",true)
	enter()
	encounter = field.crab_encounter
	player = field.pawn.player
	check(not encounter.session_active and not encounter.portal.visible,"Old victory does not force playback or unlock an unseen route")
	field.feet = encounter.patrol_feet+Vector2(80,30)
	field._sync_view(0)
	check(encounter.can_talk() and encounter.crab_prompt.can_interact(),"Peaceful crab offers the shared E prompt near old-save player")
	check(encounter.interact() and encounter.session_active and paused and player.input_frozen,"Interaction pauses exploration and opens the common dialogue")
	check(encounter.dialogue._lines.map(func(line): return line.text)==["kakakakakaka","啊？？？","qiaqiaqiaqia","啊？？？"],"All four authored dialogue lines remain exact and ordered")
	check(encounter.dialogue._lines[0].slot==TutorialDialogue.Slot.LEFT and encounter.dialogue._lines[1].slot==TutorialDialogue.Slot.RIGHT,"Dialogue portraits follow the crab and Lan's actual left/right map positions")
	await capture("salt_departure_crab_dialogue")
	encounter.dialogue.advance()
	await capture("salt_departure_lan_dialogue")
	encounter.dialogue.advance()
	encounter.dialogue.advance()
	save.fail_write = true
	encounter.dialogue.advance()
	check(not save.has_completed(encounter.DIALOGUE_FACT) and encounter.dialogue.opened and encounter.comic==null,"Failed dialogue settlement keeps the last line retryable")
	save.fail_write = false
	encounter.dialogue.advance()
	await process_frame
	var route: WindSightingComic = encounter.comic
	check(route is ComicPlayer and route.get_script().resource_path.ends_with("wind_sighting_comic.gd"),"Route reuses the existing configured common comic, without a new playback script")
	check(route._frames.size()==6 and route.panel_index==0 and route.cinematic_id==encounter.DEPARTURE_ID,"Configured route starts with six independent panels and its own viewing record")
	check(save.has_completed(encounter.DIALOGUE_FACT) and not encounter.departure_complete() and not field.hud.visible,"Dialogue, comic completion and exploration HUD stay separate")
	await capture("salt_departure_panel_01")
	route._show_panel(2,false)
	await capture("salt_departure_panel_03")
	route._show_panel(5,false)
	await capture("salt_departure_panel_06")
	save.fail_write = true
	route._request_finish(false)
	check(route._pending_completion_retry and encounter.session_active and not encounter.portal.visible,"Comic save failure preserves the shared retry view and keeps the gate locked")
	save.fail_write = false
	# Interrupt rather than complete; recovery must not require fighting again.
	field.free()
	current_scene = null
	check(not paused and save.get_cinematic_status(&"salt_to_mirror_lake")==SaveProgressService.CinematicStatus.UNHANDLED,"Interrupted comic restores pause without claiming watched or skipped")
	enter()
	encounter = field.crab_encounter
	field.feet = encounter.patrol_feet+Vector2(80,30)
	field._sync_view(0)
	check(encounter.interact() and encounter.dialogue==null and encounter.comic!=null,"Interrupted route resumes the comic after its separately saved dialogue")
	route = encounter.comic
	route._show_panel(5,false)
	route._request_finish(false)
	check((root.get_node("SceneTransition") as SceneTransitionService).is_transitioning and encounter.session_active and route.visible,"Final panel stays visible under the common scene fade")
	await wait_for_map_fade()
	field = current_scene as Chapter2SaltField
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
	encounter = field.crab_encounter
	check(not encounter.session_active and not paused and field.pawn.can_move(),"Successful completion restores exploration and the previous pause/freeze state")
	check(field.feet==encounter.ARRIVAL_FEET and encounter.patrol_feet.distance_to(encounter.RESIDENT_FEET)<80 and encounter.portal.visible,"Comic hands Lan and the crab to fixed cave-side map positions")
	check(save.get_cinematic_status(encounter.DEPARTURE_ID)==SaveProgressService.CinematicStatus.WATCHED,"Full viewing writes the shared WATCHED outcome")
	check(not save.has_completed(&"mirror_lake_entered"),"Finishing the comic is not arrival in Mirror Lake")
	var landing_clear := true
	for pile in field.piles:
		if not pile.excavated and pile.footprint().grow(18).has_point(field.feet): landing_clear = false
	check(landing_clear,"Cave-side landing stays clear of all ordinary salt heaps")
	await capture("salt_departure_cave_handoff")
	field.feet = encounter.CAVE_FEET
	field._sync_view(0)
	encounter._interaction_released = false
	check(encounter.can_use_exit() and not encounter.interact(),"The comic's last input cannot immediately trigger the gate")
	advance(1.0/60)
	field.free()
	current_scene = null
	enter()
	encounter = field.crab_encounter
	check(encounter.portal.visible and not encounter.session_active and encounter.patrol_feet==encounter.RESIDENT_FEET,"Completed-route reentry keeps the gate and peaceful resident without a forced replay")
	# Explicit skipping uses exactly the same handoff, but remains SKIPPED.
	save._config.set_value("cinematics","salt_to_mirror_lake",0)
	field.feet = encounter.patrol_feet
	encounter._start_departure()
	encounter.comic._request_finish(true)
	await wait_for_map_fade()
	field = current_scene as Chapter2SaltField
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
	encounter = field.crab_encounter
	check(save.get_cinematic_status(encounter.DEPARTURE_ID)==SaveProgressService.CinematicStatus.SKIPPED and field.feet==encounter.ARRIVAL_FEET,"Explicit skip is distinct from watching and still delivers Lan to the cave")
	check(not paused and encounter.portal.visible,"Skipping also restores control and exposes the common portal")
	field.feet = encounter.CAVE_FEET
	advance(1.0/60)
	field._sync_view(0)
	await capture("salt_departure_gate_ready")
	check(encounter.interact(),"A fresh E interaction starts the real common scene transition")
	check(not encounter.interact() and not save.has_completed(&"mirror_lake_entered"),"Transition locks duplicate entry and does not prewrite arrival")
	check(encounter.session_active and encounter.comic is WindSightingComic and paused,"First cave entry opens the configured common scroll comic")
	check(encounter.comic.cinematic_id==encounter.SCROLL_ENTRY_ID and encounter.comic._frames.size()==6,"Scroll entry has six panels and an independent viewing record")
	check((root.get_node("SceneTransition") as SceneTransitionService).current_music_path==Chapter2Music.SALT_FIELD.resource_path,"Cave comic keeps the salt-field music before the map boundary")
	encounter.comic._show_panel(5,false)
	encounter.comic._request_finish(false)
	check(save.get_cinematic_status(encounter.SCROLL_ENTRY_ID)==SaveProgressService.CinematicStatus.WATCHED and not save.has_completed(&"mirror_lake_entered"),"Scroll viewing settles before the actual arrival")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	await wait_for_map_fade()
	check(is_instance_valid(current_scene) and current_scene is MirrorLake,"Real scene transition loads the existing Mirror Lake map")
	var lake := current_scene as MirrorLake
	if lake!=null:
		check(save.has_completed(&"mirror_lake_entered") and not lake._arrival_pending,"Destination success records arrival through the existing save contract")
		check(lake.player.position.x==MirrorLake.SPAWN_X and lake.side==MirrorLake.Side.YANG,"Mirror Lake retains its normal entrance and default yang state")
		check(not lake.entry.seal_activated and not lake.entry.gate_open,"Route does not bypass the lake's seal or reed gate")
		check(transition.current_music_path==MirrorLakeMusic.EXPLORE.resource_path,"Major-map boundary uses Mirror Lake's configured exploration music")
		await capture("salt_departure_mirror_lake_arrival")
	if is_instance_valid(current_scene): current_scene.free()
	current_scene = null
	print("SALT CRAB ENCOUNTER: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
