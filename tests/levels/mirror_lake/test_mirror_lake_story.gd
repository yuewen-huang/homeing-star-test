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

	# Jump to the east bridge landing to test the local beat with real movement.
	player.reset_after_map_fall(Vector2(lake.story.ECHO_X - 142, MirrorLake.STAND_Y))
	await walk_to(lake.story.ECHO_X + 24, KEY_D)
	var echo := lake.story.echo
	check(is_instance_valid(echo) and echo.visible and player.position.x - echo.position.x > 95,
		"The reflection stays behind when Lan walks onward")
	check(not player.input_frozen and lake.story.dialogue == null, "The reflection doesn't interrupt play")
	await capture("03-reflection")
	tap(KEY_E)
	check(lake.story.dialogue != null and paused, "Nearby E opts into examining the reflection")
	tap(KEY_ESCAPE)
	check(not paused and not player.input_frozen and not memory.has_completed(lake.story.ECHO_READ), "Esc restores control without marking the reflection read")
	await wait_frames(2)
	tap(KEY_E)
	tap(KEY_SPACE)
	check(memory.has_completed(lake.story.ECHO_READ), "Finishing the reflection line records only that observation")

	player.reset_after_map_fall(Vector2(MirrorLakeInkTrial.TURTLE_X - 80, MirrorLake.STAND_Y))
	await wait_frames(12)
	check(lake.story.dialogue == null and lake.story.choices == null and lake.ink_trial.state == MirrorLakeInkTrial.State.LOCKED,
		"Walking past the turtle leaves the ink trial locked and opens no dialogue")
	tap(KEY_E)
	await capture("04-turtle-topics")
	tap(KEY_2)
	await capture("05-lan-asks")
	tap(KEY_SPACE)
	await capture("06-turtle-answers")
	for i in 3:
		tap(KEY_SPACE)
	check(memory.has_completed(lake.story.WIND_READ) and not memory.has_completed(lake.story.REFLECTION_READ),
		"Wind's clue can be learned independently of the turtle's reflection topic")
	check(not paused and not player.input_frozen and lake.ink_trial.state == MirrorLakeInkTrial.State.LOCKED,
		"Reading the story does not open the trial or leave the controls frozen")
	await wait_frames(2)
	tap(KEY_E)
	tap(KEY_1)
	for i in 4:
		tap(KEY_SPACE)
	check(memory.has_completed(lake.story.REFLECTION_READ), "The second topic remains readable in a different order")
	var faint_board := lake.story.board_reflection.modulate.a
	await wait_frames(125)
	tap(KEY_F)
	await wait_frames(32)
	check(lake.story.board_reflection.modulate.a > faint_board and not lake.panda_arena.active,
		"Yin makes the abandoned board visible without starting a Go game")
	await capture("07-unfinished-game")

	current_scene = null
	lake.queue_free()
	await wait_frames(2)
	memory._config = ConfigFile.new()
	memory.try_complete_fact(MirrorLakeEntry.SEAL_FACT)
	load_lake()
	player.reset_after_map_fall(Vector2(lake.story.GUIDE_START_X + 60.0, MirrorLake.STAND_Y))
	await wait_frames(3)
	check(not lake.story.guide.visible, "An older completed entrance does not replay the first tutorial")
	player.reset_after_map_fall(Vector2(MirrorLakeInkTrial.TURTLE_X - 160, MirrorLake.STAND_Y))
	await walk_to(PandaGoArena.TRIGGER_X + 5.0, KEY_D)
	check(lake.panda_arena.active and not paused and lake.story.choices == null and lake.story.dialogue == null,
		"Walking past every optional topic still reaches the established Panda encounter")
	check(not memory.has_completed(MirrorLakeInkTrial.INTRO_FACT) and not memory.has_completed(lake.story.WIND_READ),
		"Skipping the story grants neither knowledge nor trial progress")
	expect_save_untouched()
	finish("MIRROR LAKE STORY")
