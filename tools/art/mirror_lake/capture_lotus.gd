extends SceneTree
## Native review with a new in-memory save. No production puzzle/reward writes.
class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var scene: MirrorLake
var actor: LanPlayer
var lotus: MirrorLakeLotus
var output := ""
func _initialize() -> void: call_deferred("run")
func place(foot: Vector2) -> void:
	actor.position = foot
	actor.velocity = Vector2.ZERO
	actor.air_state = LanPlayer.AirState.GROUNDED
	actor.play_idle()
func step_leaf(index: int) -> void:
	place(lotus.position+Vector2(100,0))
	lotus.tick(0.01)
	place(lotus.position+Vector2(lotus.LEAF_X[index],lotus.DECK_Y))
	lotus.tick(0.01)
func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
	print("Captured ",name)
func run() -> void:
	output = "D:/HomingStar/homeing-star-temp-assert/artifacts/mirror_lake_lotus/review"
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	actor = scene.player as LanPlayer
	actor.set_physics_process(false)
	lotus = scene.lotus
	place(lotus.position+Vector2(-120,0))
	scene.camera_x = MirrorLake.camera_x_for(lotus.position.x+390)
	scene.camera_y = MirrorLake.CAMERA_Y_REST
	scene.update_scroll()
	scene.update_debug_label()
	lotus.clue_clock = 0.65
	lotus.tick(0.01)
	await shot("01_yang_first_ripple")
	lotus.clue_clock = lotus.CLUE_BEAT+0.65
	lotus.tick(0.01)
	await shot("02_yang_third_leaf")
	for i in 48:
		lotus.clue_clock = float(i)*0.1
		lotus.tick(0.0)
		await shot("clue_%03d" % i)
	scene.request_switch()
	scene.advance_switch(MirrorLake.SWITCH_DURATION+0.01)
	scene.update_debug_label()
	await shot("03_yin_leaves_without_red_seals")
	step_leaf(0)
	step_leaf(2)
	await shot("04_two_correct_steps")
	step_leaf(3)
	await shot("05_wrong_step_resets")
	step_leaf(0)
	step_leaf(2)
	step_leaf(1)
	lotus.tick(0.40)
	await shot("06_lotus_opening")
	for i in 60: lotus.tick(1.0/60.0)
	place(lotus.position+Vector2(220,0))
	await shot("07_red_seal_dropped")
	place(lotus.position+Vector2(lotus.FLOWER_AT.x,0))
	lotus.tick(0.02)
	await shot("08_seal_claimed")
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	quit()
