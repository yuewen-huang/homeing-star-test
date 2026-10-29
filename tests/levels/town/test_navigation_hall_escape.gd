extends "../../support/harness.gd"
## Exercise real hall entry plus Esc, and the looping hint teardown it crosses.
class TestAudioSettings extends AudioSettingsService:
	func _save_settings() -> void: pass

func press_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await wait_frames(2)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	Input.parse_input_event(event)
	await wait_frames(2)

func wait_transition() -> void:
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	var start := Time.get_ticks_msec()
	while transition.is_transitioning and Time.get_ticks_msec() - start < 10000:
		await process_frame
	check(not transition.is_transitioning, "Scene fade completes even while Esc settings pause gameplay")

func run() -> void:
	var save := use_memory_progress()
	(root.get_node("QuestLog") as QuestLogService)._save = save
	# Settings input is real; persistence is suppressed for this fixture only.
	var old_settings := root.get_node("AudioSettings")
	root.remove_child(old_settings)
	old_settings.free()
	var settings := TestAudioSettings.new()
	settings.name = "AudioSettings"
	root.add_child(settings)
	var host := Node2D.new()
	root.add_child(host)
	var dialogue := TutorialDialogue.new()
	host.add_child(dialogue)
	dialogue.play([{"text":"first"}, {"text":"second"}])
	var first := dialogue._hint_tween
	first.custom_step(0.1)
	dialogue.advance()
	check(not first.is_valid(), "Changing dialogue line stops the previous continue-hint loop")
	var second := dialogue._hint_tween
	dialogue.close()
	check(not first.is_running() and not second.is_running(), "Closing dialogue leaves no older looping hint running")
	host.queue_free()
	await wait_frames(3)
	for fact: StringName in [SaveProgressService.TUTORIAL_MOVE, SaveProgressService.TUTORIAL_JUMP,
			SaveProgressService.TUTORIAL_BREAKFAST, SaveProgressService.TUTORIAL_CLIMB,
			SaveProgressService.QUEST_CHILD_KITE_PICKED, SaveProgressService.STORY_EATING_TALK]:
		save.mark_completed(fact)
	var town: Node2D = load("res://scenes/levels/town/homeward_town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	town.player.position = Vector2(town.NAVIGATION_DOOR_X, town.STREET_BASELINE)
	await wait_frames(3)
	await press_key(KEY_E)
	check((root.get_node("SceneTransition") as SceneTransitionService).is_transitioning, "Town E starts the actual hall-entry transition")
	await press_key(KEY_ESCAPE)
	check(settings.settings_panel.visible and paused, "Esc during hall entry opens settings and pauses gameplay")
	await wait_transition()
	check(current_scene is ComicPlayer, "Hall entry comic loads while settings are open")
	await press_key(KEY_ESCAPE)
	check(not settings.settings_panel.visible and not paused, "Second Esc closes settings and resumes hall entry")
	var comic := current_scene as ComicPlayer
	for i in comic._frames.size():
		await press_key(KEY_E)
		await create_timer(0.3).timeout
	await wait_transition()
	check(current_scene.scene_file_path == "res://scenes/levels/navigation_hall/navigation_hall.tscn", "Entry completes at the real navigation hall")
	var room := current_scene
	await wait_frames(2)
	check(room.navigator_dialogue != null and room.navigator_dialogue.opened, "Navigator dialogue starts normally after entry")
	# Advance through several lines before Esc; this used to leave older loops.
	for i in 3: room.navigator_dialogue.advance()
	await press_key(KEY_ESCAPE)
	check(settings.settings_panel.visible and paused, "Esc in the hall dialogue pauses through the same settings handler")
	await press_key(KEY_ESCAPE)
	while room.navigator_dialogue != null: room.navigator_dialogue.advance()
	await wait_frames(4)
	check(not settings.settings_panel.visible and not paused and not room.player.input_frozen, "Dialogue can finish after Esc with no stuck pause or frozen player")
	current_scene = null
	room.queue_free()
	await wait_frames(4)
	expect_save_untouched()
	finish("NAVIGATION HALL ESCAPE")
