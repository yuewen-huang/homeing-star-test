extends SceneTree
## Run using the Studio project and a native renderer. No replacement drawing code.
class SwarmStage extends Node2D:
	var TIMELINE: Array = []
	var attacker := Node2D.new()
	var target := Node2D.new()
	const GROUND_Y := 520.0
	const TARGET_SIZE := Vector2(44,96)
	func _init() -> void:
		add_child(attacker)
		add_child(target)
		attacker.position = Vector2(256,300)
		target.position = Vector2(256,300)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-skill/fx")
	var view := SubViewport.new()
	view.size = Vector2i(512, 384)
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for key in ["descent_quake", "tiger_quake", "dissipate", "dissipate_idle", "dissipate_punch", "drop_trail"]:
		if "--trail-only" in OS.get_cmdline_user_args() and key != "drop_trail": continue
		var recipe: String = "dissipate" if key.begins_with("dissipate") else key
		var folder: String = "res://combos/sandstorm_" + recipe
		var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/combo.json"))
		var event: Dictionary = document.events[0]
		ComboStyle.data = JSON.parse_string(FileAccess.get_file_as_string(folder + "/style.json"))
		view.size = Vector2i(512,768) if key == "drop_trail" else Vector2i(512,384)
		view.canvas_transform = Transform2D(0, Vector2(0,160)) if key == "drop_trail" else Transform2D.IDENTITY
		var stage := SwarmStage.new()
		view.add_child(stage)
		var effect: Node2D
		var pose: String = "idle" if key == "dissipate_idle" else ("punch" if key == "dissipate_punch" else "land")
		if recipe in ["descent_quake", "tiger_quake"]:
			event.x = 256
			event.y = 300
			effect = load("res://vfx/quake_effect.gd").new().configure(event)
			effect.set_look("cel", "balanced")
		else:
			event.at = [256,520] if key == "drop_trail" else [256,300]
			if recipe == "dissipate": event.peel_segments = document.pose_segments[pose]
			if key == "drop_trail":
				for point: Array in event.path:
					point[0] -= 384
			stage.TIMELINE = [event]
			effect = load("res://vfx/swarm_effect.gd").new().configure(event, stage)
		view.add_child(effect)
		var body := Sprite2D.new()
		body.centered = false
		body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.add_child(body)
		DirAccess.make_dir_recursive_absolute(out.path_join(key))
		for i in 60:
			if i > 0: effect.advance(1.0 / 60.0)
			effect.modulate.a = 1.0 - smoothstep(.72, .98, i / 60.0)
			body.visible = recipe == "dissipate" and i < 13
			if body.visible:
				var file: String = out.get_base_dir().path_join("erosion").path_join(pose).path_join("frame_%03d.png" % i)
				body.texture = ImageTexture.create_from_image(Image.load_from_file(file))
			await process_frame
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(out.path_join(key).path_join("frame_%03d.png" % i))
		effect.free()
		body.free()
		stage.free()
	print("SANDSTORM STUDIO BAKE: quake + silhouette sand variants + vertical sand trail")
	quit()
