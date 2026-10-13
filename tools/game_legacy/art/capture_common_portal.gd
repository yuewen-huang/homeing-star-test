extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var room := load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate() as Chapter1BossRoom
	root.add_child(room)
	room.player.set_physics_process(false)
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("portal_in_boss_room.png"))
	var scene := load("res://scenes/sideview/common_portal_visual.tscn") as PackedScene
	var colors := [Color("7bd1ff"),Color("91e2a8"),Color("c9a0ff"),Color("ffc878"),Color("f3eee0")]
	var names := ["蓝色", "绿色", "紫色", "金色", "白色"]
	var portals: Array[CommonPortalVisual] = []
	for i in range(colors.size()):
		var portal := scene.instantiate() as CommonPortalVisual
		portal.position = Vector2(330+i*195,555)
		portal.glow_color = colors[i]
		portal.pulse_speed = 0.0
		room.add_child(portal)
		portals.append(portal)
		var label := Label.new()
		label.text = names[i]
		label.position = Vector2(-50,-197)
		label.size.x = 100
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("outline_size",4)
		portal.add_child(label)
	room.player.visible = false
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("portal_color_variants.png"))
	# A runtime recolor must not affect another instance's shared-looking frame.
	portals[0].glow_color = Color("ff9960")
	portals[1].active = false
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("portal_runtime_change.png"))
	var first_material := portals[0].get_node("Aura").material as ShaderMaterial
	var second_material := portals[1].get_node("Aura").material as ShaderMaterial
	assert(first_material != second_material, "Portal colors must be independent")
	assert(second_material.get_shader_parameter("glow_color") == colors[1])
	assert(second_material.get_shader_parameter("active") == false)
	print("PORTAL CHECKS: recolor and deactivate are independent; frame remains shared")
	quit()
