extends "../../tests/support/harness.gd"

const SCENE := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"
var output := ""
var level: SunkenCavern
var player: LanPlayer

func run() -> void:
	use_memory_progress()
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/cavern_entrance")
	DirAccess.make_dir_recursive_absolute(output)
	level = load(SCENE).instantiate()
	root.add_child(level)
	player = level.player
	await step(8)
	await capture("quay")
	await end_entry_test()

func release() -> void:
	for action in ["ui_left", "ui_right", "ui_up", "ui_down", "jump", "interact"]:
		Input.action_release(action)

func step(count: int) -> void:
	for i in count: await physics_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func end_entry_test() -> void:
	release()
	for type in ["AudioStreamPlayer","AudioStreamPlayer2D"]:
		for audio in root.find_children("*",type,true,false):
			audio.stop()
			audio.stream = null
	await wait_frames(3)
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("CAVERN ENTRANCE ART")
