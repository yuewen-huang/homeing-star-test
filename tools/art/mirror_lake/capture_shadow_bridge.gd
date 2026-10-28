extends SceneTree
## Isolated native-rendered review; never writes the player's progress.
class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var scene: MirrorLake
var actor: LanPlayer
var puzzle: MirrorLakeShadowBridge
var output := ""
func _initialize() -> void: call_deferred("run")
func place(x: float,y: float) -> void:
	actor.position = Vector2(x,y)
	actor.velocity = Vector2.ZERO
	actor.air_state = LanPlayer.AirState.GROUNDED
	actor.play_idle()
	scene.camera_x = MirrorLake.camera_x_for(x)
	scene.camera_y = MirrorLake.camera_y_for(y)
	scene.update_scroll()
	scene.update_debug_label()
func side(value: int) -> void:
	if scene.side == value: return
	scene.advance_switch(MirrorLake.SWITCH_COOLDOWN+0.1)
	scene.request_switch()
	scene.advance_switch(MirrorLake.SWITCH_DURATION+0.1)
func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
	print("Captured ",name)
func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty(): output = "D:/HomingStar/homeing-star-temp-assert/artifacts/mirror_lake_shadow_bridge/review"
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
	puzzle = scene.shadow_bridge
	await process_frame
	place(3800,MirrorLake.STAND_Y)
	await shot("01_yang_broken_and_complete_reflection")
	side(MirrorLake.Side.YIN)
	await shot("02_yin_shadow_bridge")
	place(3980,MirrorLakeShadowBridge.source_world_y(puzzle.bridges[0],3980))
	await shot("03_climb_to_crown_seal")
	place(puzzle.seals[0].position.x,puzzle.seals[0].position.y+2)
	puzzle.tick(0.02)
	side(MirrorLake.Side.YANG)
	await shot("04_fixed_in_yang")
	place(6150,MirrorLake.STAND_Y)
	await shot("05_fork_reflection_clue")
	side(MirrorLake.Side.YIN)
	await shot("06_yin_true_and_false_branches")
	place(puzzle.seals[1].position.x,puzzle.seals[1].position.y+2)
	puzzle.tick(0.02)
	await shot("07_high_reward")
	place(3300,MirrorLake.STAND_Y)
	side(MirrorLake.Side.YANG)
	await shot("08_pier_under_water_yang")
	side(MirrorLake.Side.YIN)
	await shot("09_pier_under_water_yin")
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	quit()
