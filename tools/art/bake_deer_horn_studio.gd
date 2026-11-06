extends SceneTree
## Run against combat-vfx-studio/project.godot. Uses its unmodified PixelSlash
## and BladeLook, not a game-side substitute renderer.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var out := "E:/HomingStar/homeing-star-test/artifacts/deer_horn_studio"
	var recipes: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(out+"/recipes.json"))
	var view:=SubViewport.new()
	view.size=Vector2i(640,512)
	view.transparent_bg=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for key in recipes:
		var folder:="res://combos/deer_horn_"+str(key)
		ComboStyle.load_file(folder+"/style.json")
		var event: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/combo.json")).events[0]
		var slash:=PixelSlash.new().configure({"shape":&"crescent","radius":float(event.radius),
			"squash":float(event.squash),"width":float(event.width),"start_angle":deg_to_rad(event.from),
			"end_angle":deg_to_rad(event.to),"duration":float(event.duration),"hold":.04,"fade":float(event.fade),
			"line_gap":6.0,"line_width":5.0,"palette":&"green"})
		slash.position=Vector2(256,384)+Vector2(recipes[key].anchor[0],recipes[key].anchor[1])
		view.add_child(slash)
		var count:=ceili((float(event.duration)+.04+float(event.fade))*60)+1
		DirAccess.make_dir_recursive_absolute(out+"/"+str(key))
		for i in count:
			if i>0: slash.advance(1.0/60)
			await process_frame
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(out+"/"+str(key)+"/frame_%03d.png"%i)
		slash.free()
	print("STUDIO HORN BAKE: four original brush crescents rendered")
	quit()
