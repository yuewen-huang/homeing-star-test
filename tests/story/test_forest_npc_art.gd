extends SceneTree
## Actual Godot assets and TutorialDialogue fit; never alter story progress.
var gallery: ForestNPCArtGallery
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Render " + label)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var before := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	gallery = load("res://scenes/dev/forest_npc_art_gallery.tscn").instantiate()
	root.add_child(gallery)
	current_scene = gallery
	await process_frame
	check(gallery.sprites.size() == 4 and gallery.portraits.size() == 4, "Four approved characters and portrait sets load")
	for i in 4:
		var sprite := gallery.sprites[i]
		var frames := sprite.sprite_frames
		check(frames.get_frame_count(&"idle") == 4 and frames.get_animation_loop(&"idle"), "Four-frame idle loop " + gallery.IDS[i])
		check(is_equal_approx(frames.get_animation_speed(&"idle"), TownNpcAnim.IDLE_FPS), "Shared three FPS base cadence")
		check(frames.get_frame_duration(&"idle", 2) < frames.get_frame_duration(&"idle", 0), "Blink is brief; neutral pose held")
		check((sprite.position + Vector2(64, 152) * sprite.scale).is_equal_approx(Vector2(260 + i * 260, 260)), "Feet anchor lands on shared floor")
		for face: Texture2D in gallery.portraits[i]:
			check(face.get_size() == Vector2(120, 107), "Native dialogue portrait canvas")
			var image := face.get_image()
			if image.is_compressed(): image.decompress()
			check(image.get_pixel(0, 0).a == 0 and image.get_used_rect().size != Vector2i.ZERO, "Transparent and nonempty portrait")
	for frame in 4:
		gallery.set_preview_frame(frame)
		await capture("forest_npcs_frame_%02d" % frame)
	for i in 4:
		gallery.show_dialogue(i, 0, TutorialDialogue.Slot.LEFT)
		await process_frame
		check(gallery.dialogue._portrait.texture == gallery.portraits[i][0], "Left frame uses prepared portrait without recropping")
		check(gallery.dialogue._cutout == TutorialDialogue.CUTOUT_LEFT, "Left cutout contract")
		await capture("forest_npc_%s_left" % gallery.IDS[i])
		gallery.show_dialogue(i, 1, TutorialDialogue.Slot.RIGHT)
		await process_frame
		check(gallery.dialogue._portrait.texture == gallery.portraits[i][1], "Right frame uses concerned portrait")
		check(gallery.dialogue._cutout == TutorialDialogue.CUTOUT_RIGHT, "Right cutout contract")
		await capture("forest_npc_%s_right" % gallery.IDS[i])
	gallery.close_dialogue()
	current_scene = null
	gallery.free()
	await process_frame
	check(before == FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH), "Art preview preserves save bytes")
	print("FOREST NPC ART: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
