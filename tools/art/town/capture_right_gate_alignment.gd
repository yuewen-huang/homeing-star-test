extends SceneTree
## Render the real master-side town gate without changing the player's save.
class MemorySave extends SaveProgressService:
	func _ready() -> void: _loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: -- <output directory> <capture label>")
		quit(1)
		return
	var old := root.get_node("SaveProgress") as SaveProgressService
	var constants: Array = old.get_script().get_script_constant_map().values()
	root.remove_child(old)
	old.free()
	var memory := MemorySave.new()
	memory.name = "SaveProgress"
	for value: Variant in constants:
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			memory._config.set_value("progress", String(value), true)
	root.add_child(memory)
	var town = load("res://scenes/levels/town/homeward_town.tscn").instantiate()
	root.add_child(town)
	current_scene = town
	town.set_process(false)
	town.player.set_physics_process(false)
	town.player.position = Vector2(4030, town.STREET_BASELINE)
	town.camera_x = town.WORLD_LENGTH - town.VIEW_WIDTH * 0.5
	town.update_scroll()
	town._update_right_gate_hint()
	town._right_gate_visual.pulse_speed = 0.0
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[0])
	var path := args[0].path_join(args[1] + ".png")
	var result := root.get_texture().get_image().save_png(path)
	print("GATE ALIGNMENT: source_x=", town.RIGHT_GATE_SOURCE_X, " anchor=", town.right_gate_hint_anchor.global_position, " rotation=", town._right_gate_visual.global_rotation, " scale=", town._right_gate_visual.global_scale)
	print("CAPTURE ", path, " error=", result)
	town.free()
	current_scene = null
	quit(result)
