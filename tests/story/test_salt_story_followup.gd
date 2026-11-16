extends "../support/harness.gd"

const SaltStory := preload("res://scripts/levels/chapter_2_salt/salt_field_story.gd")
const SALT := "res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn"

func run() -> void:
	var save := use_memory_progress()
	save.try_complete_fact(&"story_c2_anomaly_shibo_intro_read")
	var field := load(SALT).instantiate() as Chapter2SaltField
	root.add_child(field)
	current_scene = field
	await wait_frames(2)
	check(not field.has_node("Shibo") and field.salt_story.points.size() == 3,
		"The retired salt NPC is absent and the three authored clues exist")
	for spec in SaltStory.POINTS:
		var feet: Vector2 = spec[1]
		check(SaltFieldPerimeter.clamp_walker(feet).is_equal_approx(feet), spec[0] + " stays inside the playable salt field")
		field.feet = feet
		field._sync_view(0)
		await wait_frames(2)
		press(KEY_E)
		var dialogue: TutorialDialogue = field.salt_story.beat.dialogue
		check(dialogue != null and dialogue._label.text == spec[2][0][1], spec[0] + " opens its authored investigation")
		press(KEY_ESCAPE)
		check(not paused and not field.pawn.player.input_frozen and not field.boss_found, "A cancelled clue restores movement")
	check(not save.has_completed(field.crab_encounter.VICTORY), "Investigations never write boss progress")
	expect_save_untouched()
	finish("SALT INVESTIGATIONS")

func press(code: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = true
	root.push_input(key)
	key = key.duplicate()
	key.pressed = false
	root.push_input(key)
