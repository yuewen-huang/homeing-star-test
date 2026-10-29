extends SceneTree
## Placement review of the production puzzle stele, using a memory-only save.
class MemorySave extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var memory := MemorySave.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var scene := load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.ink_trial.set_physics_process(false)
	var stele := scene.puzzle_stele
	var bridges := scene.shadow_bridge.bridges
	var left := MirrorLakeShadowBridge.deck_point(bridges[0], MirrorLakeShadowBridge.CUTS[-1]).x
	var right := MirrorLakeShadowBridge.deck_point(bridges[1], MirrorLakeShadowBridge.CUTS[0]).x
	assert(stele.get_parent() == scene.world_root)
	assert(stele.position.x > left and stele.position.x < right)
	assert(is_equal_approx(stele.position.y, MirrorLake.STAND_Y))
	print("Puzzle stele at ", stele.position, "; between bridge edges ", left, " / ", right)
	scene.player.position = stele.position + Vector2(-135, 0)
	scene.camera_x = stele.position.x
	scene.camera_y = MirrorLake.CAMERA_Y_REST
	scene.update_scroll()
	var output := "E:/HomingStar/homeing-star-temp-assert/artifacts/mirror_lake_steles"
	DirAccess.make_dir_recursive_absolute(output)
	for side in 2:
		if side == MirrorLake.Side.YIN:
			scene.request_switch()
			scene.advance_switch(3)
		scene.update_debug_label()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("puzzle_placement_%d.png" % side))
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	quit()
