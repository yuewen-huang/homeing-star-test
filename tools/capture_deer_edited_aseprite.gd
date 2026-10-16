extends SceneTree
## Left: previous runtime art. Right: native user edits at original world size.

var room
var deer: DeerBoss
var reference: Sprite2D
var output := ""

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	deer = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	room.player.set_physics_process(false)
	room.player.position.x = 70
	room.dummy.position.x = 1240
	deer.position.x = 940
	reference = Sprite2D.new()
	reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reference.z_index = deer.z_index
	room.add_child(reference)
	for spec in [["idle_ING",0],["light_START",5],["light_ING",1],["light_END",3],
		["charge_run_ING",3],["flick_START",5],["leap_turn_END",4],["heavy_END",4],["getup_START",0]]:
		var id := StringName(spec[0])
		var frame: int = spec[1]
		deer.direction = 1
		deer._art_context = ""
		deer._show_clip(id, frame)
		deer.vfx._sync_body_material()
		var old_image := Image.load_from_file(output.get_base_dir().path_join("before/%s.png" % id))
		var old_frame := old_image.get_region(Rect2i(frame*256,0,256,256))
		reference.texture = ImageTexture.create_from_image(old_frame)
		reference.scale = Vector2.ONE * 1.4 * DeerActionLibrary.draw_scale(id,frame)
		reference.position = Vector2(380,deer.position.y) + deer.animated_sprite.position
		var material := deer.animated_sprite.material.duplicate() as ShaderMaterial
		material.set_shader_parameter("texture_to_logical_scale",1.0)
		reference.material = material
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s_F%02d.png" % [id,frame]))
		print("CAPTURE ",id)
	room.free()
	quit()
