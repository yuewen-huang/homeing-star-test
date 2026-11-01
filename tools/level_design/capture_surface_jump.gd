extends "../../tests/player/lan/test_lan_swimming.gd"
## Native review using production sprites and physics; saves stay in memory.

func run() -> void:
	use_memory_progress()
	build()
	var assist := root.get_node_or_null("BattleAssist")
	if assist:
		for child in assist.get_children():
			if child is CanvasLayer:
				child.visible = false
	var camera := Camera2D.new()
	camera.position = Vector2(1450, 520)
	camera.zoom = Vector2(1.3, 1.3)
	world.add_child(camera)
	await surface_from(Vector2(1500, 900))
	release_all()
	await step(3)
	await capture("float")
	Input.action_press(&"jump")
	await step(2)
	Input.action_release(&"jump")
	check(anim() == &"jump_start", "Native surface jump uses ordinary jump_start")
	await capture("jump_start")
	player.update_combat_input_buffers(DT, true, false, false)
	await step(3)
	check(anim() == &"jump_attack_1x", "Native surface jump uses existing airborne attack")
	await capture("jump_attack")
	await launch_from_surface()
	for i in 20:
		if player.can_start_double_jump(): break
		await step(1)
	Input.action_press(&"ui_right")
	Input.action_press(&"jump")
	await step(3)
	release_all()
	check(anim() == &"double_jump_forward", "Native surface jump uses existing forward double jump")
	await capture("double_jump")
	expect_save_untouched()
	finish("SURFACE JUMP VISUAL")

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/lan_surface_jump_20261031/%s.png" % label)
	check(root.get_texture().get_image().save_png(out) == OK, "Screenshot saved: " + label)
