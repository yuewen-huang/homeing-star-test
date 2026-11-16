extends "../support/harness.gd"

const STORY := preload("res://scripts/story/chapter_1_forest_dialogue.gd")
const PROLOGUE := preload("res://scripts/story/prologue_dialogue.gd")
const FACTS := preload("res://scripts/story/forest_story_facts.gd")
const MIST := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
const WIND := "res://scenes/levels/chapter_1/chapter_1_wind_room.tscn"
const ROOT := "res://scenes/levels/chapter_1/chapter_1_root_room.tscn"
const VINE := "res://scenes/levels/chapter_1/chapter_1_vine_room.tscn"
const DEER := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"


func run() -> void:
	var save := use_memory_progress()
	if "--vine-only" in OS.get_cmdline_user_args():
		save.try_complete_fact(FACTS.XIAOYA_RESCUED)
		await verify_vine_gate(save)
		expect_save_untouched()
		finish("VINE GATE TO DEER INTRO")
		return
	if "--root-only" in OS.get_cmdline_user_args():
		save.try_complete_facts([FACTS.CAMPFIRE_READ, FACTS.STAR_CHART_READ])
		await verify_root_rescue(save)
		expect_save_untouched()
		finish("ROOT RESCUE")
		return
	save.try_complete_facts([SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED, PROLOGUE.MASTER_TRIAL_HEARD])
	var room := await enter_map(WIND)
	var chart := room.get_node("WindStarChart")
	await stand_at(room, chart.position + Vector2(-44, 0))
	press(KEY_E)
	check(chart.dialogue == null and not save.has_completed(FACTS.STAR_CHART_READ),
		"Early exploration of the canopy keeps the next story beat locked")
	check(room.get_node_or_null("Terrain/Entrance/LetterBag") == null, "The retired letter bag never spawns")
	var tower := room.get_node("WatchtowerLog")
	await stand_at(room, tower.position + Vector2(-55, 0))
	await capture("wind_watchtower_world")
	press(KEY_E)
	await read_lines(tower.dialogue, [STORY.WATCHTOWER_LOG, STORY.WATCHTOWER_LINE], {0: "wind_watchtower_log"})
	check(save.has_completed(FACTS.WATCHTOWER_LOG_READ) and not save.has_completed(FACTS.CAMPFIRE_READ)
		and not save.has_completed(FACTS.STAR_CHART_READ), "The watchtower log is readable on its own")
	room = await enter_map(MIST)
	var camp := room.get_node_or_null("WindCampfire")
	check(camp != null and room.has_node("WindRouteMark"), "New first arrival places both clues")
	if camp == null:
		finish("MIST STORY OPENING")
		return
	check(save.has_completed(SaveProgressService.STORY_C1_FOREST_ENTERED), "Arrival is recorded on actual entry")
	check(not paused and not room.player.input_frozen and room.yupo.dialogue == null, "Arrival leaves Lan in control")
	await stand_at(room, camp.position + Vector2(-42, 0))
	press(KEY_E)
	check(camp.dialogue == null and not save.has_completed(FACTS.CAMPFIRE_READ), "Campfire cannot be read out of order")

	var route_mark: Node2D = room.get_node("WindRouteMark")
	await stand_at(room, route_mark.position + Vector2(-55, 0))
	await capture("mist_route_mark_with_herbs")
	await stand_at(room, room.yupo.position + Vector2(-46, 0))
	await capture("mist_yupo_world")
	press(KEY_E)
	check(room.yupo.dialogue != null and paused and room.player.input_frozen, "Existing NPC interaction opens new dialogue")
	press(KEY_E)
	press(KEY_ESCAPE)
	check(not paused and not room.player.input_frozen and not save.has_completed(FACTS.ENTRY_HEARD),
		"Esc restores control and leaves the lead unread")
	await wait_frames(2)
	press(KEY_E)
	var entry_lines: Array[String] = []
	for line in STORY.ENTRY_TEXT:
		entry_lines.append(line[2])
	await read_lines(room.yupo.dialogue, entry_lines, {0: "mist_yupo_first_line", 6: "mist_yupo_herbs"})
	check(save.has_completed(FACTS.ENTRY_HEARD) and not paused and not room.player.input_frozen, "Full dialogue settles the lead")
	check(not save.has_completed(FACTS.YUPO) and not save.has_completed(SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED),
		"The new lead never records the legacy greeting or message quest")
	await wait_frames(2)
	press(KEY_E)
	check(room.yupo.dialogue == null and room.yupo.choices == null, "A follow-up press does not replay or offer old topics")
	await capture("mist_yupo_after_gift")
	await stand_at(room, route_mark.position + Vector2(-55, 0))
	await capture("mist_route_mark_after_gift")

	await stand_at(room, Vector2(1125, room.FLOOR_Y))
	Input.action_press("ui_right")
	for frame in 180:
		if room.player.position.x >= 1310.0:
			break
		await physics_frame
	Input.action_release("ui_right")
	check(room.player.position.x >= 1310.0 and not paused and not room.player.input_frozen,
		"Lan crosses the whisper zone using normal movement")
	for index in STORY.MIST_WHISPERS.size():
		for frame in 900:
			if room._whisper_index >= index:
				break
			await process_frame
		var bubble := room.get_node_or_null("MistWhisperLayer/MistWhispers") as CharacterBubble
		check(bubble != null and bubble.visible and bubble._label.text == STORY.MIST_WHISPERS[index],
			"Whisper beat %d matches the script" % (index + 1))
		check(bubble != null and bubble.show_tail == (index == 2) and not paused and not room.player.input_frozen,
			"Whisper beat %d leaves movement available and identifies Lan's reply" % (index + 1))
		await capture("mist_whisper_%d" % (index + 1))
	check(not save.has_completed(FACTS.MIST_WHISPERS_HEARD), "Starting the final bubble does not settle it early")
	for frame in 900:
		if save.has_completed(FACTS.MIST_WHISPERS_HEARD):
			break
		await process_frame
	check(save.has_completed(FACTS.MIST_WHISPERS_HEARD), "The full ambient beat settles after the final line")

	await stand_at(room, camp.position + Vector2(-48, 0))
	await capture("mist_campfire_world")
	press(KEY_E)
	check(camp.dialogue != null and not save.has_completed(FACTS.CAMPFIRE_READ), "The campfire is available after the lead")
	press(KEY_ESCAPE)
	check(not paused and not save.has_completed(FACTS.CAMPFIRE_READ), "Leaving the fire unread is retryable")
	await wait_frames(2)
	press(KEY_E)
	await read_lines(camp.dialogue, [STORY.CAMPFIRE_DESCRIPTION, STORY.CAMPFIRE_LINE], {1: "mist_campfire_line"})
	check(save.has_completed(FACTS.CAMPFIRE_READ) and not paused and not room.player.input_frozen,
		"Finishing records the wound clue without a core fight")
	check(save.get_stele_state(room.COMBAT_ID) == MinigameStele.SteleState.LOCKED, "Inspection leaves the trial alone")
	var border := room.get_node("BorderStele")
	await stand_at(room, border.position + Vector2(-42, 0))
	await capture("mist_border_stele_world")
	press(KEY_E)
	await read_lines(border.dialogue, [STORY.BORDER_STELE_TEXT], {0: "mist_border_stele_read"})
	check(save.has_completed(FACTS.BORDER_STELE_READ) and not save.has_completed(FACTS.STAR_CHART_READ),
		"The border stone records only the inscription")
	room = await enter_map(MIST)
	check(save.has_completed(FACTS.CAMPFIRE_READ) and not room.get_node("WindCampfire").prompt.available,
		"The investigation does not replay on re-entry")
	await stand_at(room, Vector2(1300, room.FLOOR_Y))
	check(room.get_node_or_null("MistWhisperLayer/MistWhispers") == null, "Re-entry does not repeat the completed ambient beat")

	var wind_gate: Node2D = room.get_node("WindSteps/WindStep4/PortalToWind")
	await stand_at(room, wind_gate.global_position)
	press(KEY_E)
	for frame in 600:
		if current_scene != null and current_scene.scene_file_path == WIND \
				and not (root.get_node("SceneTransition") as SceneTransitionService).is_transitioning:
			break
		await process_frame
	room = current_scene
	check(is_instance_valid(room) and room.scene_file_path == WIND, "The real mist portal reaches wind without a core fight")
	if not is_instance_valid(room) or room.scene_file_path != WIND:
		finish("MIST AND WIND STORY")
		return
	chart = room.get_node("WindStarChart")
	await stand_at(room, chart.position + Vector2(-44, 0))
	await capture("wind_star_chart_world")
	press(KEY_E)
	check(chart.dialogue != null, "The chart is available after the campfire")
	press(KEY_ESCAPE)
	check(not save.has_completed(FACTS.STAR_CHART_READ) and not paused, "Interrupting inspection leaves the chart in place")
	await wait_frames(2)
	press(KEY_E)
	await read_lines(chart.dialogue, [STORY.STAR_CHART_DESCRIPTION, STORY.STAR_CHART_LINE], {1: "wind_star_chart_read"})
	check(save.has_completed(FACTS.STAR_CHART_READ) and not paused and not room.player.input_frozen, "Reading settles the chart independently")
	check(save.get_stele_state(room.COMBAT_ID) == MinigameStele.SteleState.LOCKED, "Reading the chart never completes the wind trial")
	await capture("wind_star_chart_taken")
	room = await enter_map(WIND)
	check(not room.get_node("WindStarChart").prompt.available, "A return visit never grants a second chart")

	await verify_root_rescue(save)
	await verify_vine_gate(save)

	save._config = ConfigFile.new()
	save.try_complete_facts([SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED,
		SaveProgressService.STORY_C1_FOREST_ENTERED, SaveProgressService.STORY_C1_YUPO_MET,
		SaveProgressService.QUEST_C1_YU_MESSAGE_ACCEPTED, SaveProgressService.QUEST_C1_WEST_ROPE_ACCEPTED,
		SaveProgressService.QUEST_C1_LETTER_BAG_ACCEPTED])
	room = await enter_map(MIST)
	check(not save.has_completed(FACTS.ENTRY_HEARD) and not room.has_node("ReturningFootprints")
		and not room.has_node("StoryPoints/WindTrace"), "Legacy flags neither complete nor restore old mist story")
	await stand_at(room, room.yupo.position + Vector2(-46, 0))
	press(KEY_E)
	check(room.yupo.dialogue != null and room.yupo.dialogue.get_line_progress().y == 8, "Old saves get only the revised dialogue")
	press(KEY_ESCAPE)
	room = await enter_map(ROOT)
	check(not room.has_node("OvertightenedPost") and not room.has_node("Logs/LogWest/WestRopeClasp"), "Retired root quest props never respawn")
	room = await enter_map(VINE)
	check(not room.has_node("RejoinedRope") and not room.has_node("BoundRoad") and not room.has_node("StoryPoints/WindSighting"),
		"Vine exploration has no retired message quest or sighting")
	check(room._portals.all(func(entry): return entry.prompt.available), "Vine portals remain open without the chart or cores")
	expect_save_untouched()
	finish("FOREST STORY THROUGH THE DEER INTRO")


func verify_root_rescue(save: MemoryProgress) -> void:
	var room := await enter_map(ROOT) as Chapter1RootRoom
	var xiaoya := room.get_node("XiaoyaRescue")
	var idle := xiaoya.get_node("Idle") as AnimatedSprite2D
	check(idle.sprite_frames.resource_path.ends_with("/xiaoya/idle_frames.tres"),
		"Root rescue uses Xiaoya's crouched sprite set")
	var approach: Vector2 = xiaoya.position - Vector2(160, 0)
	var slash := room.get_node("RootSlashMarks")
	await stand_at(room, slash.position + Vector2(-60, 0))
	await capture("root_slash_world")
	press(KEY_E)
	await read_lines(slash.dialogue, [STORY.ROOT_SLASH_DESCRIPTION], {0: "root_slash_read"})
	check(save.has_completed(FACTS.ROOT_SLASH_MARKS_READ) and not save.has_completed(FACTS.XIAOYA_RESCUED),
		"Reading the cut roots records an observation without completing the rescue")

	# Remove each finished reading separately to exercise both sides of the guard.
	var both_read := save._config.encode_to_text()
	for missing: StringName in [FACTS.CAMPFIRE_READ, FACTS.STAR_CHART_READ]:
		save._config.set_value("progress", String(missing), false)
		await stand_at(room, xiaoya.position - Vector2(66, 0))
		press(KEY_E)
		check(not xiaoya.visible and xiaoya.dialogue == null and not paused,
			"Neither walking up nor pressing E triggers rescue with missing fact: " + String(missing))
		await stand_at(room, approach)
		save._config = ConfigFile.new()
		save._config.parse(both_read)
	await capture("root_xiaoya_world")
	Input.action_press("ui_right")
	for frame in 120:
		if xiaoya.dialogue != null:
			break
		await physics_frame
	Input.action_release("ui_right")
	check(xiaoya.dialogue != null and paused and room.player.input_frozen,
		"With both readings complete, walking up to the stele starts the rescue automatically")
	press(KEY_E)
	press(KEY_ESCAPE)
	await wait_frames(2)
	check(xiaoya.visible and xiaoya.dialogue == null and not paused and not room.player.input_frozen
		and not save.has_completed(FACTS.XIAOYA_RESCUED), "Esc leaves Xiaoya in place without settling the rescue")
	press(KEY_E)
	check(xiaoya.dialogue._actors[&"xiaoya"].current.texture == STORY.XIAOYA_FRIGHTENED,
		"The rescue starts with Xiaoya gripping her basket in the normal dialogue frame")
	var rescue_lines: Array[String] = []
	rescue_lines.assign(STORY.RESCUE_TEXT)
	await read_lines(xiaoya.dialogue, rescue_lines, {0: "root_xiaoya_first", 2: "root_xiaoya_recognizes", 4: "root_xiaoya_wind", 7: "root_xiaoya_last"})
	await wait_frames(2)
	check(save.has_completed(FACTS.XIAOYA_RESCUED) and not xiaoya.visible and not paused and not room.player.input_frozen,
		"Completing the authored dialogue settles the rescue and returns control")
	check(save.get_stele_state(room.COMBAT_ID) == MinigameStele.SteleState.LOCKED \
		and room._portals.all(func(gate): return gate.prompt.available),
		"The root core, challenge and open map remain independent of the rescue")
	room = await enter_map(ROOT) as Chapter1RootRoom
	xiaoya = room.get_node("XiaoyaRescue")
	await stand_at(room, xiaoya.position - Vector2(66, 0))
	check(not xiaoya.visible and xiaoya.dialogue == null and not paused, "Returning never replays a completed rescue")


func verify_vine_gate(save: MemoryProgress) -> void:
	var room := await enter_map(VINE) as Chapter1VineRoom
	var altar := room.get_node("VineAltar")
	await stand_at(room, altar.position + Vector2(-60, 0))
	await capture("vine_altar_world")
	press(KEY_E)
	check(altar.dialogue != null and not room.puzzle.can_interact(),
		"The altar opens independently from the west")
	press(KEY_E)
	press(KEY_ESCAPE)
	await wait_frames(2)
	check(not save.has_completed(FACTS.VINE_ALTAR_READ) and not paused, "Leaving the main stele unread does not unlock the story")
	await stand_at(room, room.get_node("Portals/HeartGate").position)
	press(KEY_E)
	check(room._stone_gate_story.dialogue == null and not save.has_completed(FACTS.VINE_STONE_GATE_SEEN),
		"Rescue alone cannot start the stone gate dialogue")
	await wait_for_deer_intro()

	room = await enter_map(VINE) as Chapter1VineRoom
	altar = room.get_node("VineAltar")
	await stand_at(room, altar.position + Vector2(60, 0))
	check(not room.puzzle.can_interact(), "The altar approach from the east is outside the optional puzzle stele range")
	press(KEY_E)
	await read_lines(altar.dialogue, [STORY.VINE_ALTAR_INSCRIPTION, STORY.VINE_ALTAR_LINE], {0: "vine_altar_read"})
	check(save.has_completed(FACTS.VINE_ALTAR_READ) and not save.has_completed(FACTS.VINE_STONE_GATE_SEEN),
		"Reading the full inscription records only the inspection")
	var both_complete := save._config.encode_to_text()
	save._config.set_value("progress", String(FACTS.XIAOYA_RESCUED), false)
	await stand_at(room, room.get_node("Portals/HeartGate").position)
	press(KEY_E)
	check(room._stone_gate_story.dialogue == null and not save.has_completed(FACTS.VINE_STONE_GATE_SEEN),
		"The inscription alone cannot start the stone gate dialogue")
	await wait_for_deer_intro()

	save._config = ConfigFile.new()
	save._config.parse(both_complete)
	room = await enter_map(VINE) as Chapter1VineRoom
	await stand_at(room, room.get_node("Portals/HeartGate").position + Vector2(-62, 0))
	await capture("vine_stone_gate_world")
	press(KEY_E)
	var gate := room._stone_gate_story
	check(gate.dialogue != null and paused and current_scene == room
		and not save.has_completed(FACTS.VINE_STONE_GATE_SEEN), "Both completed events unlock the stone gate dialogue")
	check(not gate.gate_visual.visible and not gate.gate_prompt.available and not room.player.visible,
		"The story hides the world gate, prompt and player sprite behind the dialogue staging")
	press(KEY_ESCAPE)
	await wait_frames(2)
	check(gate.dialogue == null and not paused and not room.player.input_frozen
		and not save.has_completed(FACTS.VINE_STONE_GATE_SEEN), "Cancelling frees movement and allows retry")
	check(gate.gate_visual.visible and gate.gate_prompt.available and room.player.visible,
		"Cancelling restores the world gate, prompt and player sprite")
	press(KEY_E)
	var gate_lines: Array[String] = []
	gate_lines.assign(STORY.VINE_GATE_TEXT)
	await read_lines(gate.dialogue, gate_lines, {0: "vine_gate_closed", 2: "vine_gate_ajar", 4: "vine_gate_wind_glance",
		5: "vine_gate_wind_looks_up", 7: "vine_gate_lan_reply", 9: "vine_gate_vines"})
	check(save.has_completed(FACTS.VINE_STONE_GATE_SEEN), "Only completing the original story records the stone gate as seen")
	check(save.get_stele_state(Chapter1VineRoom.COMBAT_ID) == MinigameStele.SteleState.LOCKED,
		"The optional vine trial never gates or settles the story")
	var deer_room := await wait_for_deer_intro()
	if deer_room != null:
		await capture("vine_gate_into_existing_deer_intro")
		press(KEY_ESCAPE)
		await wait_frames(2)
		check(deer_room.encounter.active and not paused and not deer_room.player.input_frozen,
			"The existing encounter starts after its original intro")
	room = await enter_map(VINE) as Chapter1VineRoom
	await stand_at(room, room.get_node("Portals/HeartGate").position)
	press(KEY_E)
	check(room._stone_gate_story.dialogue == null and save.has_completed(FACTS.VINE_STONE_GATE_SEEN),
		"The completed scene is not forced to replay when re-entering")
	await wait_for_deer_intro()


func wait_for_deer_intro() -> Chapter1DeerBossRoom:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for frame in 600:
		if current_scene != null and current_scene.scene_file_path == DEER and not transition.is_transitioning:
			break
		await process_frame
	var room := current_scene as Chapter1DeerBossRoom
	check(room != null and room.story.comic != null and room.story.comic.panels.size() == 6,
		"The existing deer intro follows the same open portal")
	return room


func enter_map(scene: String) -> Node:
	assert(change_scene_to_file(scene) == OK)
	await scene_changed
	await wait_frames(2)
	return current_scene


func stand_at(room: Node, at: Vector2) -> void:
	room.player.position = at
	room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED
	await wait_frames(2)
	room.camera.reset_smoothing()
	room.camera.force_update_scroll()


func read_lines(dialogue: TutorialDialogue, expected: Array[String], shots: Dictionary) -> void:
	if dialogue == null:
		check(false, "Expected an open dialogue")
		return
	for index in expected.size():
		check(dialogue.get_line_progress().x == index and dialogue._label.text == expected[index],
			"Line %d matches the authored text" % (index + 1))
		press(KEY_E)
		await process_frame
		check(dialogue.get_line_progress().x == index and dialogue._label.visible_characters == expected[index].length()
			and dialogue._label.get_line_count() == dialogue._label.get_visible_line_count(),
			"First press reveals line %d without advancing or clipping" % (index + 1))
		if expected[index] == STORY.RESCUE_TEXT[3]:
			check(dialogue._actors[&"xiaoya"].current.texture == STORY.XIAOYA_RELIEVED,
				"Xiaoya eases her grip after hearing about the lit lamp")
		if expected[index] == STORY.VINE_GATE_TEXT[4]:
			var wind = dialogue._actors.get(&"wind")
			check(dialogue._active_id == &"wind" and wind != null
				and wind.current.texture == STORY.WIND_LOOKS_BACK
				and dialogue._actors[&"gate"].current.texture == STORY.GATE_AJAR,
				"The approved Wind portrait appears together with the ajar stone gate")
		if expected[index] == STORY.VINE_GATE_TEXT[5]:
			check(dialogue._actors[&"wind"].current.texture == STORY.WIND_LOOKS_UP,
				"Wind looks up toward the vines after the authored cue")
		if expected[index] == STORY.VINE_GATE_TEXT[9]:
			check(dialogue._actors[&"gate"].current.texture == STORY.GATE_VINES,
				"The thorn vines cover the gate on the original line")
		if shots.has(index):
			await capture(shots[index])
		press(KEY_E)


func press(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func capture(filename: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	if not paused:
		var location_title := root.get_node_or_null("SceneTransition/LocationTitle/TitleSurface") as Control
		for frame in 240:
			if location_title == null or not location_title.is_visible_in_tree():
				break
			await process_frame
	await create_timer(0.24).timeout
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(output.path_join(filename + ".png")) == OK,
		"Captured " + filename)
