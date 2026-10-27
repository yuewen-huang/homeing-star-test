extends "../../support/harness.gd"
## Run with -Visual: GPU readback verifies the ribbon reaches the final room framebuffer.

func frame_image() -> Image:
	for i in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func changed_ink(before: Image, after: Image, gold: bool) -> int:
	var count := 0
	for y in range(0,after.get_height(),2):
		for x in range(0,after.get_width(),2):
			var a := before.get_pixel(x,y)
			var b := after.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b) < 0.08: continue
			if gold:
				if b.r > b.b*1.2 and b.g > b.b*1.1: count += 1
			else:
				var steel := b.b > b.r*1.06 and b.g > b.r*1.04
				var bone := absf(b.r-.945)+absf(b.g-.933)+absf(b.b-.894)<.09
				if steel or bone: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false,"Render regression requires run-tests.ps1 -Visual")
		finish("MASTER FLYING SWORD RENDER")
		return
	use_memory_progress()
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	dev.select_combo_library(8)
	dev.play_action(4)
	# Keep everything static while comparing visible and hidden ribbon framebuffers.
	dev.process_mode = Node.PROCESS_MODE_DISABLED
	var formation := dev.adapter.master.get_node("FlyingSwordPreview") as MasterFlyingSwordFormation
	formation.self_stepping = false
	for sword in formation.swords: sword.hide()
	var seen := 0
	for i in 1800:
		formation.advance(1.0/240.0)
		var barrage := formation.barrage
		if not is_instance_valid(barrage) or not is_instance_valid(barrage.active): continue
		var ribbon := barrage.active
		if barrage.slash_count <= seen or ribbon.age < ribbon.duration*0.55: continue
		seen = barrage.slash_count
		barrage.hide()
		var without := await frame_image()
		if seen in [8,9]:
			barrage.sword.show()
			var weapon := await frame_image()
			check(changed_ink(without,weapon,seen == 9) > 20,"Weapon itself renders %s on cut %d" % ["gold" if seen == 9 else "blue",seen])
			barrage.sword.hide()
		if seen == 1:
			barrage.z_index = 0
			barrage.show()
			var behind := await frame_image()
			check(changed_ink(without,behind,false) == 0,"Reproduces the old failure: z=-1 ribbon is hidden by the room background")
			barrage.z_index = barrage.sword.z_index
		barrage.show()
		var visible := await frame_image()
		var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
		if not output.is_empty(): visible.save_png(output.path_join("flying_cut_%d.png" % seen))
		var texture_image := ribbon.render_viewport.get_texture().get_image()
		var clear_border := true
		for x in texture_image.get_width():
			clear_border = clear_border and texture_image.get_pixel(x,0).a == 0 and texture_image.get_pixel(x,texture_image.get_height()-1).a == 0
		for y in texture_image.get_height():
			clear_border = clear_border and texture_image.get_pixel(0,y).a == 0 and texture_image.get_pixel(texture_image.get_width()-1,y).a == 0
		check(clear_border,"Cut %d leaves a transparent render-texture border instead of clipping against its edge" % seen)
		var pixels := changed_ink(without,visible,seen == 9)
		check(pixels > 100,"Cut %d draws %d visible %s ribbon pixels over the actual room background" % [seen,pixels,"gold" if seen == 9 else "blue"])
		if seen == 9: break
	check(seen == 9,"All nine slashes reach the final rendered framebuffer")
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FLYING SWORD RENDER")
