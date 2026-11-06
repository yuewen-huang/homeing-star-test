extends SceneTree
## Run with the Studio project. Bake its original quake renderer, including its dust atlas.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out:="E:/HomingStar/homeing-star-test/artifacts/deer_dust_studio"
	var view:=SubViewport.new()
	view.size=Vector2i(512,384)
	view.transparent_bg=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for key in ["trail","lift","rain"]:
		var folder: String="res://combos/deer_dust_"+key
		var event: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/combo.json")).events[0]
		event.x=256
		event.y=280
		var dust: Node2D=load("res://vfx/quake_effect.gd").new().configure(event)
		dust.set_look("cel","balanced")
		view.add_child(dust)
		DirAccess.make_dir_recursive_absolute(out+"/"+key)
		for i in 42:
			if i>0: dust.advance(1.0/60)
			dust.modulate.a=1-smoothstep(.42,.68,i/60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(out+"/"+key+"/frame_%03d.png"%i)
		dust.free()
	print("STUDIO DUST BAKE: three original quake recipes")
	quit()
