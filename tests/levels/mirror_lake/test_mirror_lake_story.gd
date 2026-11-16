extends "../../support/harness.gd"

var lake: MirrorLake
var player: LanPlayer
var memory: MemoryProgress


func load_lake() -> void:
	lake = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(lake)
	current_scene = lake
	player = lake.player as LanPlayer


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func tap(code: Key) -> void:
	key(code, true)
	key(code, false)


func walk_to(x: float, code: Key) -> void:
	key(code, true)
	for i in 520:
		await physics_frame
		if player.position.x >= x:
			break
	key(code, false)
	await wait_frames(2)


func capture(name: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "Captured " + name)


func run() -> void:
	Input.use_accumulated_input = false
	memory = use_memory_progress()
	root.get_node("QuestLog")._save = memory
	load_lake()
	await wait_frames(4)
	check(not lake.story.guide.visible and not player.input_frozen, "Arrival leaves the first shoreline free to explore")
	await walk_to(lake.story.GUIDE_START_X + 45.0, KEY_D)
	check(lake.story.guide.visible and not player.input_frozen, "Approaching the first seal shows the single switch guide with live controls")
	check(lake.story._guide_title.text.contains("F") and lake.story._guide_detail.text.contains("方向颠倒"), "The guide shows the bound switch key and the actual direction rule")
	await capture("01-first-switch")
	tap(KEY_F)
	await wait_frames(32)
	check(lake.side == MirrorLake.Side.YIN and lake.controls_inverted() and lake.story.guide.visible, "Real F input switches the scene and the guide acknowledges it")
	check(memory.has_completed(lake.story.SWITCH_LEARNED), "The lesson records the successful switch")
	await capture("02-yin")
	await walk_to(MirrorLakeEntry.SEAL_X + 6.0, KEY_A)
	check(lake.entry.gate_open and memory.has_completed(MirrorLakeEntry.SEAL_FACT), "Real reversed input reaches the seal and opens the original gate")
	await wait_frames(125)
	check(not lake.story.guide.visible, "The lesson disappears on its own")
	tap(KEY_F)
	await wait_frames(35)
	check(lake.side == MirrorLake.Side.YANG and not lake.story.guide.visible, "Switching back doesn't reopen the lesson")

	player.reset_after_map_fall(Vector2(MirrorLakeInkTrial.TURTLE_X - 65, MirrorLake.STAND_Y))
	await wait_frames(12)
	check(lake.story.dialogue == null and lake.ink_trial.state == MirrorLakeInkTrial.State.LOCKED,
		"The optional ink trial waits for interaction")
	tap(KEY_E)
	check(lake.story.dialogue != null and paused, "E opens the ink trial instructions directly")
	tap(KEY_ESCAPE)
	check(not paused and not player.input_frozen and lake.ink_trial.state == MirrorLakeInkTrial.State.LOCKED,
		"Cancelling the lesson does not start the trial")
	player.reset_after_map_fall(Vector2(PandaGoArena.TRIGGER_X - 140.0, MirrorLake.STAND_Y))
	await walk_to(PandaGoArena.TRIGGER_X + 2.0, KEY_D)
	check(not lake.panda_arena.active and lake.chapter_story.beat.dialogue != null and paused,
		"Walking past the optional trial opens Xuanbai's prebattle dialogue")
	for index in 6: tap(KEY_SPACE)
	check(lake.panda_arena.active and not paused, "The original boss encounter follows the revised lines")
	check(not memory.has_completed(MirrorLakeInkTrial.INTRO_FACT), "The battle does not require the optional tutorial")
	expect_save_untouched()
	finish("MIRROR LAKE STORY")
