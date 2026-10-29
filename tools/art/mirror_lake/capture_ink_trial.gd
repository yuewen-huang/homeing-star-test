extends SceneTree
## Native render evidence; replaces the save service in memory before loading the lake.
class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var scene: MirrorLake
var output := "E:/HomingStar/homeing-star-temp-assert/artifacts/mirror_lake_ink_trial"
func _initialize() -> void: call_deferred("run")
func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	var player := scene.player as LanPlayer
	player.set_physics_process(false)
	var trial := scene.ink_trial
	trial.set_physics_process(false)
	player.position.x = trial.TURTLE_X - 110
	scene.camera_x = MirrorLake.camera_x_for(trial.TURTLE_X + 100)
	scene.update_scroll()
	scene.update_debug_label()
	await shot("01_yang_bixi")
	trial.tick(0.01)
	await shot("02_turtle_dialogue_right")
	trial.dialogue.advance()
	await shot("03_lan_dialogue_left")
	while trial.dialogue != null: trial.dialogue.advance()
	scene.request_switch()
	scene.advance_switch(3)
	player.position.x = trial.STELE_X - 160
	trial.receive_hit(1, player.global_position)
	trial.receive_hit(1, player.global_position)
	await shot("04_yin_charging")
	for i in 3: trial.receive_hit(1, player.global_position)
	scene.request_switch()
	scene.advance_switch(3)
	trial.tick(trial.RELEASE_DELAY + 0.01)
	trial.hitbox.set_physics_process(false)
	trial.stroke.advance(0.04)
	await shot("05a_mouth_emission")
	trial.tick(0.10)
	await shot("05_ink_stroke")
	trial.tick(0.08)
	await shot("05b_full_horizontal")
	trial._reset_round()
	trial.successes = 2
	trial.state = MirrorLakeInkTrial.State.SETTLING
	trial._try_complete()
	trial._refresh()
	await shot("06_complete")
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	quit()
