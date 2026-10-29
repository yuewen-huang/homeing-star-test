extends SceneTree
## Mirror Lake progress-stele art review only. Does not place steles in the production map.
class MemorySave extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
var output := "E:/HomingStar/homeing-star-temp-assert/artifacts/mirror_lake_steles"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
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
	scene.player.position = Vector2(500, MirrorLake.STAND_Y)
	scene.camera_x = 900
	scene.update_scroll()
	var specimens: Array[MinigameStele] = []
	for i in 2:
		var kind := "puzzle" if i == 0 else "combat"
		var stele := load("res://scenes/levels/mirror_lake/mirror_lake_%s_stele.tscn" % kind).instantiate() as MinigameStele
		stele.position = Vector2(800 + i * 410, MirrorLake.STAND_Y)
		scene.world_root.add_child(stele)
		stele.bind_player(scene.player)
		specimens.append(stele)
		var title := Label.new()
		title.text = "镜湖 · " + stele.get_kind_name()
		title.position = Vector2(-90, -stele.display_height - 46)
		title.add_theme_font_size_override("font_size", 21)
		title.add_theme_color_override("font_color", Color("333b3b"))
		title.add_theme_color_override("font_outline_color", Color("eee8dc"))
		title.add_theme_constant_override("outline_size", 4)
		stele.add_child(title)
	for state in 3:
		for stele in specimens:
			assert(memory.set_stele_state(stele.stele_id, state))
		await process_frame
		for stele in specimens:
			stele._info_label.visible = true
			stele.set_process(false)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("steles_%d.png" % state))
		print("Rendered stele state ", state)
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	quit()
