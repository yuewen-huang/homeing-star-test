extends "../../support/harness.gd"
var room: Chapter1DeerBossRoom
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))
func run() -> void:
	var save := use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	room=load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	var intro := WindSightingComic.new()
	var packed := PackedScene.new()
	packed.pack(intro)
	intro.free()
	room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	await wait_frames(3)
	check(room.encounter.active and room.deer is DeerDuelBoss,"Real room begins the approved first-phase actor")
	check(room.player.get_script().resource_path.ends_with("/lan_player.gd") and not room.player.combat_stats.refill_health_on_depletion,"Production room keeps ordinary player death, not development refill")
	check(not room._return_prompt.available,"Return gate is closed during the live battle")
	# Survival is a test fixture only; production was checked above with assistance off.
	assist.set_player_invincible(true)
	for phase in range(1,5):
		var actor := room.deer
		var old_host := room.encounter.host
		check(actor.get_script()==DeerEncounter.ACTORS[phase-1] and actor.phase==phase,"Phase %d uses the same production class as its accepted development room"%phase)
		check(not actor.manual_control and actor.is_physics_processing(),"Phase %d runs real autonomous AI"%phase)
		for frame in 270: await physics_frame
		check(not actor.move_history.is_empty() or phase==2,"Phase %d advances its actual attack clock"%phase)
		await capture("production_phase_%d"%phase)
		if phase==2:
			check(actor.terrain.roots.size()>0 and actor.terrain.age>2.4,"Production root phase creates the real contest terrain")
		if phase==4:
			check(room.encounter.transformation_progress()==1.0,"Fourth phase completes the authored human transformation")
		actor.combat_stats.apply_health_damage(actor.combat_stats.health)
		check(room.encounter.transitioning and actor.invulnerable and not actor.is_physics_processing(),"Phase %d depletion stops attacks and enters one protected handoff"%phase)
		check(not save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED),"Phase %d does not settle victory before the final presentation completes"%phase)
		for frame in 180:
			await physics_frame
			if room.encounter.phase!=phase or room.encounter.complete: break
		await wait_frames(2)
		if phase<4:
			check(room.encounter.phase==phase+1 and not is_instance_valid(old_host),"Phase %d retires its entire effect/terrain subtree before the next phase"%phase)
			check(room.encounter.get_child_count()==1,"Only one phase owns active combat nodes")
		else:
			check(room.encounter.complete and room.story._settled,"Only fourth-phase final presentation completes the encounter")
	if room.story.comic!=null:
		room.story.comic.playback_finished.emit(true)
		await wait_frames(2)
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and save.get_item_count(ItemCatalog.DEER_RELIC)==1,"Actual full progression settles victory and exactly one relic after the aftermath")
	check(room.story.resident!=null and not room.deer.visible and room._return_prompt.available,"Victory replaces combat actor with resident and opens return passage")
	if room.story.reward_reveal!=null: room.story.reward_reveal._finish_reveal()
	await wait_frames(2)
	check(room.story.chapter_gate.visible,"Closing reward presentation unlocks the real chapter-two gate")
	check(room.player.world_min_x<room.get_node("ReturnGate").position.x and room.player.world_max_x>room.story.chapter_gate.position.x,"Victory restores exploration bounds so both real exits are reachable")
	await capture("production_victory")
	current_scene=null
	room.free()
	await wait_frames(2)
	expect_save_untouched()
	finish("DEER PRODUCTION ENCOUNTER")
