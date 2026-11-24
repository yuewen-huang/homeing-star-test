extends "../../support/harness.gd"

const Facts := preload("res://scripts/story/forest_story_facts.gd")
const Dialogue := preload("res://scripts/story/chapter_1_deer_dialogue.gd")
var room: Chapter1DeerBossRoom

func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK, "Captured " + label)

func run() -> void:
	var save := use_memory_progress()
	save.try_complete_facts([Facts.CAMPFIRE_READ, Facts.STAR_CHART_READ, Facts.XIAOYA_RESCUED,
		Facts.VINE_ALTAR_READ, Facts.VINE_STONE_GATE_SEEN])
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
		if phase==1:
			await see_fight_line(Dialogue.FIGHT_LINES[0][0], "deer_fight_warning")
		if phase==3:
			for words in Dialogue.FIGHT_LINES[2]:
				await see_fight_line(words, "deer_fight_phase_change" if words == Dialogue.FIGHT_LINES[2][0] else "")
		for frame in 270: await physics_frame
		check(not actor.move_history.is_empty() or phase==2,"Phase %d advances its actual attack clock"%phase)
		await capture("production_phase_%d"%phase)
		if phase==2:
			check(actor.terrain.roots.size()>0 and actor.terrain.age>2.4,"Production root phase creates the real contest terrain")
			actor.receive_attack_hit(AttackHitContext.new(&"attack_1", 1, 0), room.player.global_position)
			for words in Dialogue.FIGHT_LINES[1]:
				await see_fight_line(words, "deer_fight_lan_reacts" if words == Dialogue.FIGHT_LINES[1][1] else "")
		if phase==4:
			check(room.encounter.transformation_progress()==1.0,"Fourth phase completes the authored human transformation")
			var health := actor.combat_stats.health
			actor.receive_attack_hit(AttackHitContext.new(&"attack_1", ceili(health * 0.8), 0), room.player.global_position)
			for words in Dialogue.FIGHT_LINES[3]:
				await see_fight_line(words, "deer_fight_lan_vow" if words == Dialogue.FIGHT_LINES[3][3] else "")
		var final_hit := AttackHitContext.new(&"attack_1", actor.combat_stats.health, 0)
		actor.receive_attack_hit(final_hit, room.player.global_position)
		check(room.has_node("BossFinisherEffect") == (phase == 4), "Phase %d only plays the finisher for the final defeat" % phase)
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
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and save.get_item_count(ItemCatalog.DEER_RELIC)==1,"Actual full progression settles victory and exactly one relic")
	check(room.story.comic == null and not room.deer.visible and room._return_prompt.available,
		"Victory opens the return passage without the retired aftermath or resident")
	check(room.story.dialogue != null and paused and not room.story.chapter_gate.visible,
		"Fourth phase completes before the release starts and before the old route can open")
	check(not room.story.get_node("DeerFightCallouts/DeerFightBubble").visible,
		"Victory clears combat bubbles before the paused ending")
	var release_lines: Array = Dialogue.RELEASE.duplicate()
	release_lines.append_array([Dialogue.REUNION, Dialogue.YUPO_GOODBYE, Dialogue.XIAOYA_GOODBYE])
	await read_ending(release_lines, {0: "deer_farewell", 1: "deer_dissolves", 2: "deer_release",
		3: "deer_reunion_entry", 4: "deer_reunion", 5: "deer_reunion_farewell"})
	check(save.has_completed(Facts.DEER_RELEASE_READ), "Only reading the release and farewell settles the aftermath")
	if room.story.reward_reveal!=null: room.story.reward_reveal._finish_reveal()
	await wait_frames(2)
	check(room.story.chapter_gate.visible,"Closing reward presentation unlocks the real chapter-two gate")
	check(room.story.rematch_prompt.available, "Victory enables the rematch at the arena entrance")
	check(room.player.world_min_x<room.get_node("ReturnGate").position.x and room.player.world_max_x>room.story.chapter_gate.position.x,"Victory restores exploration bounds so both real exits are reachable")
	await capture("production_victory")
	Input.action_press("ui_right")
	for frame in 720:
		if room.story.chapter_prompt.can_interact(): break
		await physics_frame
	Input.action_release("ui_right")
	check(room.story.chapter_prompt.can_interact(), "Normal movement reaches the old route interaction at %s" % room.player.position)
	press(KEY_E)
	check(room.story.dialogue != null and paused and not save.has_completed(Facts.OLD_ROUTE_READ),
		"E at the real exit opens the monologue before leaving")
	press(KEY_ESCAPE)
	check(not paused and current_scene == room and not save.has_completed(Facts.OLD_ROUTE_READ),
		"Esc leaves the old route unread and keeps Lan in the arena")
	press(KEY_E)
	await read_ending([Dialogue.ROAD_OPENS, Dialogue.LAN_RECALLS, Dialogue.LAN_RESOLVES,
		Dialogue.LAN_TO_WIND, Dialogue.LAN_STEPS_FORWARD], {0: "old_route_opens", 1: "old_route_recall", 4: "old_route_departure"})
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	if is_instance_valid(room.story.comic):
		for frame in 120:
			if not room.story.comic._changing_panel: break
			await process_frame
		press(KEY_ESCAPE)
	for frame in 900:
		if current_scene is Chapter2SaltField and not transition.is_transitioning: break
		await process_frame
	check(save.has_completed(Facts.OLD_ROUTE_READ) and current_scene is Chapter2SaltField
		and transition.current_music_path == Chapter2Music.SALT_FIELD.resource_path,
		"Reading and advancing the last line enters the existing chapter-two salt field")
	check(range(4).all(func(region: int): return not save.has_completed(ForestCoreRelic.victory_id(region))),
		"The story reaches chapter two with all four optional cores untouched")
	await capture("chapter_2_arrival")
	expect_save_untouched()
	finish("DEER PRODUCTION ENCOUNTER")


func see_fight_line(words: String, shot: String) -> void:
	var bubble := room.story.get_node("DeerFightCallouts/DeerFightBubble") as CharacterBubble
	for frame in 360:
		if bubble.visible and bubble._label.text == words: break
		await physics_frame
	check(bubble.visible and bubble._label.text == words and not paused and not room.player.input_frozen,
		"Real combat cue preserves player control: " + words)
	if not shot.is_empty():
		await capture(shot)


func read_ending(lines: Array, shots: Dictionary) -> void:
	var dialogue := room.story.dialogue
	if dialogue == null:
		check(false, "Expected a readable ending")
		return
	for index in lines.size():
		check(dialogue._label.text == lines[index], "Ending uses the original script, line %d" % index)
		press(KEY_E)
		await process_frame
		check(dialogue.get_line_progress().x == index and dialogue._label.visible_characters == dialogue._label.text.length()
			and dialogue._label.get_visible_line_count() == dialogue._label.get_line_count(),
			"Quick reveal fits and stays on this line")
		if lines[index] in [Dialogue.YUPO_GOODBYE, Dialogue.XIAOYA_GOODBYE]:
			check(room.story.comic == null and dialogue._active_cast == [&"scene", &"family"]
				and dialogue._actors[&"family"].current.texture == Dialogue.FAMILY_FAREWELL,
				"The reunion keeps both squirrels in the original dialogue frame")
		if lines[index] == Dialogue.RELEASE[1]:
			check(room.story.comic == null and dialogue._actors[&"scene"].current.texture == Dialogue.DEER_DISSOLVES,
				"The original release dialogue uses the restored deer image at the cue")
		if lines[index] == Dialogue.LAN_TO_WIND:
			check(dialogue._active_id == &"lan" and dialogue._actors[&"lan"].current.texture == Dialogue.STOWS_CHART,
				"Lan stows the chart in the original dialogue frame")
		if shots.has(index):
			if DisplayServer.get_name() != "headless": await create_timer(0.22).timeout
			await capture(shots[index])
		press(KEY_E)
		await process_frame


func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
