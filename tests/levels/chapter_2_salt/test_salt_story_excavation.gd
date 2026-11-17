extends "../../support/harness.gd"

const SALT := preload("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn")
const STORY := preload("res://scripts/levels/chapter_2_salt/salt_field_story.gd")
const TEXT := preload("res://scripts/story/chapter_2_dialogue.gd")

class FailableProgress extends MemoryProgress:
	var refuse := false
	func save_progress() -> bool: return not refuse

var field: Chapter2SaltField


func run() -> void:
	var previous := use_memory_progress()
	root.remove_child(previous)
	previous.free()
	var save := FailableProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	save._config.set_value("map_states", "chapter_2_salt_field", {"boss_pile": 1, "dug": []})
	save.try_complete_fact(STORY.ENTRY_READ)
	await enter()
	excavate(4)
	await process_frame
	check(field.worms.worms[4].attacks == 1 and field.worms.worms[4].sprite.visible, "The first ordinary excavation starts a real worm attack")
	check(save.has_completed(STORY.FIRST_WORM) and field.salt_story._bubble._label.text == TEXT.SALT_WORM_BUBBLE,
		"The real eruption gives Lan her once-only reaction")
	check(not paused and not field.pawn.player.input_frozen, "The ambush bubble leaves controls live")
	field.worms.step(0.11)
	await capture("salt_first_worm")
	await wait_frames(220)
	excavate(5)
	save.refuse = true
	excavate(6)
	check(not field.piles[6].excavated and not field.has_node("DigClue_MerchantBell"),
		"A failed third excavation creates neither a hole nor an object")
	save.refuse = false
	excavate(6)
	await process_frame
	check(field.state.story_clues["merchant_bell"] == 6 and field.has_node("DigClue_MerchantBell")
		and field.salt_story._bubble._label.text == TEXT.SALT_BELL_BUBBLE, "The third saved dig places the merchant bell")
	check(field.dig_hint.is_empty(), "A discovered object does not show the generic empty-pit hint")
	var feet_before := field.feet
	field.step_exploration(0.05, Vector2.RIGHT, false, false)
	check(field.feet != feet_before and not paused, "Lan can move while the discovery bubble is onscreen")
	await capture("salt_merchant_bell")
	await wait_frames(250)
	for id in [7, 8, 9]:
		excavate(id)
	await process_frame
	check(field.state.story_clues["wind_cloak"] == 9 and field.has_node("DigClue_WindCloak")
		and field.salt_story._bubble._label.text == TEXT.SALT_CLOTH_BUBBLE, "The sixth dig places Wind's cloak fragment")
	await capture("salt_wind_cloak")
	await wait_frames(250)
	excavate(25)
	await process_frame
	var pit = field.worms.worms[25]
	check(field.state.story_clues["tainted_crystal"] == 25 and field.has_node("DigClue_TaintedCrystal")
		and field.salt_story._bubble._label.text == TEXT.SALT_MIST_BUBBLE, "A later excavation close to the saved crab reveals crystals")
	pit.begin_attack()
	check(pit.suppressed and pit.attacks == 0, "The crystal clue pit cannot erupt")
	await capture("salt_crystal_mist", 22)
	field.queue_free()
	await wait_frames(3)
	await enter()
	check(field.state.boss_pile == 1 and field.has_node("DigClue_MerchantBell")
		and field.has_node("DigClue_WindCloak") and field.has_node("DigClue_TaintedCrystal"),
		"Re-entry restores the exact objects and the crab's original location")
	check(field.worms.worms[25].suppressed and field.salt_story._pending_bubbles.is_empty(),
		"Re-entry keeps the tainted pit inert without replaying the discovery")
	field.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("SALT STORY EXCAVATION")


func enter() -> void:
	field = SALT.instantiate() as Chapter2SaltField
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0.0
	await process_frame


func excavate(id: int) -> void:
	field.feet = field.piles[id].ground_position + Vector2(0, 42)
	field._sync_view(0)
	field.target = id
	field._finish_dig()


func capture(label: String, frames := 3) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await wait_frames(frames)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Captured " + label)
