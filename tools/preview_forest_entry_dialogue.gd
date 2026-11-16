extends "../tests/support/harness.gd"

const MIST_PATH := "res://scenes/levels/chapter_1/chapter_1_mist_room.tscn"
const STORY_PATH := "res://scripts/story/chapter_1_forest_dialogue.gd"
const PROLOGUE := preload("res://scripts/story/prologue_dialogue.gd")


func run() -> void:
	var save := use_memory_progress()
	var walk := "--walk" in OS.get_cmdline_user_args()
	if walk:
		save.try_complete_facts([SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED, PROLOGUE.MASTER_TRIAL_HEARD])
	var room := (load(MIST_PATH) as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	if walk:
		return
	var player := room.get("player") as LanPlayer
	var yupo := room.get("yupo") as Node2D
	player.position = yupo.position + Vector2(-62, 0)
	await process_frame
	paused = true
	var story := load(STORY_PATH)
	var dialogue: TutorialDialogue = story.play_yupo_entry(room, player)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(dialogue, player)
	else:
		dialogue.finished.connect(func(): quit(), CONNECT_ONE_SHOT)


func _capture(dialogue: TutorialDialogue, player: LanPlayer) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		push_error("Set HOMING_STAR_TEST_OUTPUT to the preview capture directory.")
		quit(1)
		return
	var shots := {0: "01_yupo_recognizes_stranger", 3: "02_yupo_remembers", 7: "03_lan_offers_herbs"}
	for i in dialogue.get_line_progress().y:
		var input := InputEventKey.new()
		input.physical_keycode = KEY_E
		input.keycode = KEY_E
		input.pressed = true
		root.push_input(input)
		await process_frame
		var label := dialogue._label
		if dialogue.get_line_progress().x != i or label.visible_characters != label.text.length() \
				or label.get_line_count() != label.get_visible_line_count():
			push_error("Dialogue did not reveal or fit line %d." % (i + 1))
			quit(1)
			return
		if shots.has(i) and DisplayServer.get_name() != "headless":
			await create_timer(0.22, true).timeout
			RenderingServer.force_draw(false)
			var image := root.get_texture().get_image()
			if image == null or image.save_png(output.path_join(shots[i] + ".png")) != OK:
				push_error("Could not capture %s." % shots[i])
				quit(1)
				return
		root.push_input(input)
	if dialogue.opened or player.input_frozen:
		push_error("Ending the preview did not restore control.")
		quit(1)
		return
	print("Forest dialogue preview: all 8 lines, typing skip, layout and control recovery passed")
	quit()
