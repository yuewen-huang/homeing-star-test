extends "../support/harness.gd"

const PROLOGUE := preload("res://scripts/story/prologue_dialogue.gd")
const STAGED := preload("res://scripts/ui/main_story_dialogue.gd")
const COLLECTION := preload("res://scripts/levels/lan_home/home_collection.gd")
const TOWN := "res://scenes/levels/town/homeward_town.tscn"
const ROOM := "res://scenes/levels/tutorial/tutorial_battle_room.tscn"
const FOREST_ENTRY := "res://scenes/story/comics/forest_entry_comic.tscn"
const FOREST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
var route: SceneTransitionService


func enter(path: String) -> Node:
	var result := change_scene_to_file(path)
	assert(result == OK)
	await scene_changed
	route._location_title.dismiss()
	return current_scene


func wait_route() -> void:
	var deadline := Time.get_ticks_msec() + 16000
	while route.is_transitioning and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not route.is_transitioning, "The current fade completes")


func press_e() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_E
	event.physical_keycode = KEY_E
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func go_to(town: Node, x: float) -> void:
	town.player.position = Vector2(x, town.STREET_BASELINE)
	town.snap_camera_to_player()
	town._update_aberration_progression()


func capture(label: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK,
		"Capture " + label)


func finish_lines(dialogue: TutorialDialogue, key: String) -> bool:
	check(dialogue != null and dialogue is STAGED and dialogue.opened, key + " uses the new UI")
	if dialogue == null:
		return false
	var expected: Array = PROLOGUE.TEXT[key]
	for index in expected.size():
		check(dialogue.get_line_progress().x == index
			and dialogue._label.text == expected[index]["text"], "%s keeps line %d" % [key, index + 1])
		dialogue.advance()
	return true


func run() -> void:
	var save := use_memory_progress()
	route = root.get_node("SceneTransition") as SceneTransitionService
	for flag: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST, SaveProgressService.TUTORIAL_CLIMB,
			SaveProgressService.STORY_EATING_TALK, SaveProgressService.QUEST_CHILD_KITE_PICKED,
			SaveProgressService.QUEST_ENTER_HALL, SaveProgressService.QUEST_FIRST_SIGHT_STEP,
			SaveProgressService.QUEST_LAN_AND_WIND_STEP, SaveProgressService.STORY_LAN_AND_WIND_TALK,
			SaveProgressService.STORY_MAGIC_SHOP_TALK, SaveProgressService.STORY_HANGOVER_PILL_EQUIPPED,
			SaveProgressService.STORY_BACK_ALLEY_ENTERED, SaveProgressService.QUEST_BACK_ALLEY_STEP,
			SaveProgressService.STORY_ABERRATION_CALLOUTS_COMPLETE,
			SaveProgressService.STORY_ABERRATION_STAFF_ARRIVED, PROLOGUE.MASTER_WOKE_HEARD,
			PROLOGUE.DUSK_BLACKOUT_SEEN, PROLOGUE.DUSK_GUIDANCE_HEARD]:
		save.mark_completed(flag)
	var quest_log := root.get_node("QuestLog") as QuestLogService
	quest_log._save = save
	quest_log._refresh()

	var town := await enter(TOWN)
	go_to(town, town.NAVIGATION_DOOR_X)
	var hall := town.aberration_escape_comic as ComicPlayer
	check(hall != null and hall._frames.size() == 5, "Real entrance opens the revised Hall comic")
	if hall == null:
		finish("PROLOGUE FINALE")
		return
	press_e()
	var hall_index := 0
	for panel in [1, 2, 3]:
		check(hall.panel_index == panel and hall._caption != null and not hall.input_enabled,
			"Authored scene %d gives its text sole ownership of input" % panel)
		var dialogue := hall._caption as TutorialDialogue
		if dialogue == null:
			finish("PROLOGUE FINALE")
			return
		if panel == 2:
			dialogue._complete_line()
			hall._fade_tween.custom_step(0.4)
			await capture("13-hall-recognition")
		for index in dialogue.get_line_progress().y:
			check(dialogue._label.text == PROLOGUE.HALL_CONFRONTATION[hall_index]["text"],
				"Hall keeps line %d" % (hall_index + 1))
			hall_index += 1
			dialogue.advance()
	check(hall_index == 5 and hall.panel_index == 4 and hall.input_enabled,
		"All five lines play before the reused escape picture")
	check(not save.has_completed(PROLOGUE.HALL_CONFRONTATION_SEEN),
		"Reading the confrontation has not completed the escape")
	hall._fade_tween.custom_step(0.4)
	press_e()
	check(save.has_completed(PROLOGUE.HALL_CONFRONTATION_SEEN)
		and save.has_completed(SaveProgressService.QUEST_ABERRATION_STEP), "Hall completion settles both facts")
	var runner := town.world_root.get_node_or_null("BlackCloakWindRunner") as Node2D
	if runner != null:
		check(is_equal_approx(runner.position.y, town.STREET_BASELINE), "Wind still runs at street level")
	var shout := town.world_root.get_node_or_null("PrologueChaseCallout") as CharacterBubble
	check(shout != null and shout._label.text == PROLOGUE.CHASE_CALLOUT, "Lan's pursuit line plays as a bubble")
	go_to(town, town.MASTER_NPC_X)
	var cutin := town.aberration_master_cutin as ComicPlayer
	check(cutin != null, "The stage still uses the approved falling sword frame")
	if cutin == null:
		finish("PROLOGUE FINALE")
		return
	await create_timer(0.35).timeout
	press_e()
	check(save.has_completed(SaveProgressService.QUEST_ABERRATION_CHASE_STEP), "Sword frame still settles the chase")
	await wait_frames(2)

	var master: Node = town.world_root.get_node("Master")
	master.player = town.player
	master.player_in_range = true
	press_e()
	var staged := master._dialogue as TutorialDialogue
	if staged != null:
		staged.advance()
		staged._complete_line()
		check(staged._actors[&"lan"].current.texture.resource_path.ends_with("gate_stunned.png"),
			"Lan changes pose midway through the gate-opening line")
		staged.advance()
		staged._complete_line()
		await create_timer(0.22).timeout
		await capture("14-hooded-wind")
		staged.advance()
	var crossing := master.get_node_or_null("PrologueFinaleComic") as ComicPlayer
	check(crossing != null and crossing._image.texture.resource_path.ends_with("wind_crosses_gate.png"),
		"Wind's farewell flows into the South Gate picture")
	if crossing == null:
		finish("PROLOGUE FINALE")
		return
	press_e()
	check(save.has_completed(PROLOGUE.WIND_LEFT_GATE), "Viewing the exit records Wind's departure")
	if not finish_lines(master._dialogue as TutorialDialogue, "gate_trial"):
		finish("PROLOGUE FINALE")
		return
	await wait_route()
	check(current_scene.scene_file_path == ROOM and save.has_completed(PROLOGUE.MASTER_TRIAL_HEARD),
		"Rayne's challenge enters the existing boss room")
	var room := current_scene
	var boss := room.boss as MasterBoss
	var lan := room.player as LanPlayer
	boss.set_process(false)
	boss.set_physics_process(false)
	var calls := room.get_node_or_null("PrologueMasterFightCallouts")
	check(calls != null and not room.is_rematch, "The story callouts are available on first trial")
	if calls == null:
		finish("PROLOGUE FINALE")
		return
	boss.voice.stop()
	boss.state = MasterBoss.State.PHASE_1_ACTION
	lan.combat_stats.apply_health_damage(1)
	calls._process(0.01)
	check(not boss.voice.is_speaking(), "The first line waits through the active swing")
	boss.state = MasterBoss.State.RECOVER
	boss.play_idle()
	calls._process(0.01)
	check(boss.voice.is_speaking() and boss.voice.stream == MasterVoice.CALLOUTS[0], "The health loss line plays after recovery")
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	boss.voice.stop()
	boss.state = MasterBoss.State.PHASE_1_ACTION
	feedback.parry_landed.emit(boss, null, Vector2.ZERO, false)
	calls._process(3.1)
	check(not boss.voice.is_speaking(), "The parry line waits through the rest of the attack")
	boss.state = MasterBoss.State.RECOVER
	boss.play_idle()
	calls._process(0.01)
	check(boss.voice.is_speaking() and boss.voice.stream == MasterVoice.CALLOUTS[1], "The parry line plays after recovery")
	boss._enter_phase_2()
	calls._process(0.01)
	boss._process(0.01)
	check(boss.phase == 1 and boss.animated_sprite.animation == &"idle" and lan.input_frozen
		and boss.voice.is_speaking() and boss.voice.stream == MasterVoice.PHASE_TWO_INTRO,
		"Rayne says the complete line before the transformation")
	var health_before_intro := boss.combat_stats.health
	boss.receive_hit(1, lan.global_position)
	boss._process(0.01)
	check(boss.phase == 1 and boss.combat_stats.health == health_before_intro and boss.attack_hitbox.attack == null,
		"Combat stays suspended while the phase intro is speaking")
	boss.voice.stop()
	boss._process(0.01)
	check(boss.phase == 2 and boss.animated_sprite.animation == &"phase_2_transform" and lan.input_frozen,
		"An already-ended intro also advances to the transformation")
	boss._on_body_animation_finished()
	check(boss.state == MasterBoss.State.PHASE_2_IDLE and not lan.input_frozen,
		"Player control returns after the transformation animation")
	check(not boss.voice.is_speaking() and not room.has_node("PrologueMasterFightCallout"),
		"Combat callouts only play voice and never create overhead dialogue")
	boss.combat_stats.apply_health_damage(boss.combat_stats.max_health)
	var deadline := Time.get_ticks_msec() + 9000
	while room.get_node_or_null("MasterFinalSendoff") == null and Time.get_ticks_msec() < deadline:
		await process_frame
	var sendoff := room.get_node_or_null("MasterFinalSendoff")
	check(sendoff != null and save.has_completed(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED)
		and not save.has_completed(PROLOGUE.MASTER_SENDOFF_HEARD), "Victory is saved before the sendoff starts")
	if sendoff == null:
		finish("PROLOGUE FINALE")
		return
	press_e()
	check(save.has_completed(PROLOGUE.MASTER_SENDOFF_COMIC_SEEN) and sendoff._dialogue != null,
		"The yielding picture leads into the final lines")

	town = await enter(TOWN)
	go_to(town, town.MASTER_NPC_X)
	town._update_right_gate_hint()
	check(not town.right_gate_hint.available, "Interrupting the sendoff keeps the departure gate pending")
	master = town.world_root.get_node("Master")
	master.player = town.player
	master.player_in_range = true
	press_e()
	sendoff = master.get_node_or_null("MasterFinalSendoff")
	check(sendoff != null and sendoff._dialogue != null, "E resumes the unread sendoff in town")
	if sendoff == null:
		finish("PROLOGUE FINALE")
		return
	staged = sendoff._dialogue as TutorialDialogue
	if staged != null:
		staged._complete_line()
		await capture("15-rayne-yields-dialogue")
	if not finish_lines(staged, "gate_sendoff"):
		finish("PROLOGUE FINALE")
		return
	var gift := master._core_gift as MasterCoreGift
	check(gift != null and gift.dialogue == null and gift.reveal != null
		and save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 1,
		"The pendant is granted and revealed directly without dialogue")
	if gift == null or gift.reveal == null:
		finish("PROLOGUE FINALE")
		return
	gift.reveal._finish_reveal()
	await wait_frames(2)
	town._update_right_gate_hint()
	check(not town.player.input_frozen and town.right_gate_hint.available,
		"The player chooses when to leave after the final dialogue and gift")
	go_to(town, town.RIGHT_GATE_X)
	await physics_frame
	await wait_frames(3)
	check(town.right_gate_hint.can_interact() and not master.player_in_range,
		"South Gate is in range after leaving Rayne's interaction area")
	press_e()
	await wait_route()
	check(current_scene.scene_file_path == FOREST_ENTRY, "South Gate E uses the original forest entry comic")
	var entrance := current_scene as ComicPlayer
	if entrance != null:
		for index in entrance._frames.size():
			press_e()
			if entrance._changing_panel:
				entrance._fade_tween.custom_step(0.4)
		await wait_route()
		check(current_scene.scene_file_path == FOREST
			and save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED),
			"The exit comic reaches actual Chapter One and records arrival there")
	var progress := save.get_completed_tutorials()
	var book_index := COLLECTION.COMICS.find(["南门放行", "res://scenes/story/comics/prologue_master_yields.tscn"])
	check(book_index >= 0 and COLLECTION.comic_panels(book_index).size() == 1
		and save.get_completed_tutorials() == progress, "The sendoff is replayable without writing progress")
	expect_save_untouched()
	finish("PROLOGUE FINALE")
