extends "../../support/harness.gd"
var room: BossDevelopmentRoom

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label+".png"))

func run() -> void:
	use_memory_progress()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	for index in BossDevelopmentRoom.BOSS_CATALOG.size():
		if BossDevelopmentRoom.BOSS_CATALOG[index].adapter.resource_path.ends_with("deer_vine_pursuit_adapter.gd"):
			room.select_boss(index)
			break
	await process_frame
	var deer: Node2D = room.adapter.deer
	var preview: Node2D = room.adapter.plow_preview
	var origin := deer.position
	var player_health: int = room.player.combat_stats.health
	check(room.segment_row.visible, "Source motion uses existing segment controls")
	room.play_segment(&"ALL")
	var seen := {}
	var snapshots := {}
	for f in 205:
		seen[preview.source_frame] = true
		if preview.source_frame in [9,17,22,31] and not snapshots.has(preview.source_frame):
			snapshots[preview.source_frame] = true
			await capture("plow_left_%02d" % (preview.source_frame+1))
		await physics_frame
	check(seen.size()==32, "Native playback visits all 32 authored frames")
	check(preview.finished and preview.source_frame==31, "Full playback holds the real final pose")
	check(absf(preview.elapsed-3.2)<.04, "Original 3.2-second timeline preserved")
	check(deer.position==origin, "Source canvas travel is not added to world movement")
	check(room.player.combat_stats.health==player_health and deer.attack_hitbox.attack==null, "Source preview produces no combat contacts")
	check(preview.sprite.flip_h, "Left-facing source preview mirrors consistently")
	room.adapter.set_preview_target(origin+Vector2(400,0))
	check(room.adapter.play_segment(0,&"ING"), "Run and lift can be inspected together")
	for f in 81: await physics_frame
	check(preview.finished and preview.source_frame==22 and not preview.sprite.flip_h, "Right-facing ING includes the complete uppercut")
	await capture("plow_right_uppercut")
	room.set_combat_simulation(true)
	check(not preview.active and deer.visible and deer.is_physics_processing(), "Starting combat restores the real deer")
	check(not room.adapter.play_segment(0,&"ALL"), "Source preview cannot interrupt real combat")
	room.set_combat_simulation(false)
	room.play_segment(&"END")
	room.adapter.play_action(0)
	check(not preview.active and deer.visible and deer.is_physics_processing(), "Existing manual attacks leave source preview cleanly")
	room.play_segment(&"ALL")
	room.reset_room()
	await process_frame
	check(not is_instance_valid(preview), "Retry releases the old preview node")
	check(room.adapter.deer.visible and room.adapter.deer.is_physics_processing(), "Retry restores the specimen")
	current_scene = null
	room.free()
	for f in 4: await process_frame
	expect_save_untouched()
	finish("DEER PLOW SOURCE PREVIEW")
