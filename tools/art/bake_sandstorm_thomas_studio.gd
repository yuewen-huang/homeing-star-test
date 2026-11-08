extends SceneTree
class SwarmStage extends Node2D:
	var TIMELINE: Array = []
	var attacker := Node2D.new()
	var target := Node2D.new()
	const GROUND_Y := 520.0
	const TARGET_SIZE := Vector2(44,96)
	func _init() -> void:
		add_child(attacker)
		add_child(target)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := "res://combos/sandstorm_thomas_wave/"
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"combo.json"))
	ComboStyle.data = JSON.parse_string(FileAccess.get_file_as_string(folder+"style.json"))
	var out := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-thomas/fx")
	DirAccess.make_dir_recursive_absolute(out)
	var view := SubViewport.new()
	view.size = Vector2i(640,384)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	view.canvas_transform = Transform2D(0,Vector2(-320,-168))
	var stage := SwarmStage.new()
	stage.TIMELINE = document.events
	view.add_child(stage)
	var effects: Array[Node2D] = []
	for event: Dictionary in document.events:
		var effect: Node2D = load("res://vfx/swarm_effect.gd").new().configure(event,stage)
		view.add_child(effect)
		effects.append(effect)
		effect.advance(.15)
	for i in 60:
		for effect in effects:
			if i>0: effect.advance(1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png(out.path_join("frame_%03d.png" % i))
	print("THOMAS STUDIO BAKE: 60 frames, concentric sand arc, radius 260, origin (320,352)")
	quit()
