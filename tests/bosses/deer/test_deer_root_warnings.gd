extends "../../support/harness.gd"
func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer: DeerBoss = room.adapter.deer
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	deer.phase = 2
	deer.reset_phase(true,false)
	deer.position = Vector2(900,555)
	room.player.position = Vector2(560,555)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var volley := deer.root_phase.spawn_tracking()
	volley.step(.7)
	deer.vfx._update_gold_warning()
	check(is_equal_approx(deer.gold_warning_age(),DangerFlash.PEAK_TIME),"Gold peak precedes first root release by shared lead")
	check(deer.vfx.gold_warning.visible,"Root attack displays shared chest gold cue")
	check(volley._telegraph._used == 3,"Tracking cluster warns all three authored footprints")
	check(not volley._telegraph.z_as_relative and volley._telegraph.z_index < SideviewLayers.PLAYER,"Floor warnings use stable layer below Lan")
	var ids := []
	for mark in volley._telegraph._marks: ids.append(mark.get_instance_id())
	for i in 120: volley._update_warnings()
	check(volley._telegraph._marks.size() == ids.size() and volley._telegraph._marks[0].get_instance_id() == ids[0],"Warning updates reuse sprite instances")
	await shot("tracking_hard")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NIGHTMARE)
	volley._update_warnings()
	deer.vfx._update_gold_warning()
	check(volley._telegraph._used == 0 and deer.vfx.gold_warning.visible,"Nightmare removes range marks but retains chest gold")
	await shot("tracking_nightmare")
	volley.cancelled = true
	deer.vfx._update_gold_warning()
	check(not deer.vfx.gold_warning.visible and volley._telegraph._used == 0,"Cancelled volley removes both warning channels")
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	var final := deer.root_phase.spawn_tide()
	final.step(.3)
	deer.vfx._update_gold_warning()
	check(final._telegraph._used > 0,"Directional tide warns before roots emerge")
	check(not final.full_floor.has_area() and final._spikes.size()<=6,"Tide keeps a safe rear route instead of full-floor collision")
	await shot("directional_tide")
	deer.root_phase.cancel_attacks()
	deer.vfx._update_gold_warning()
	check(not deer.vfx.gold_warning.visible,"Phase cleanup removes chest warning")
	var nodule := deer.root_phase.add_nodule(Vector2(560,555))
	var launch := deer.root_phase.spawn_nodule_launch(nodule)
	launch.step(.5)
	deer.vfx._update_gold_warning()
	check(launch.active_rects().is_empty() and deer.vfx.gold_warning.visible,"Nodule launch now warns before any damage window")
	launch.step(.14)
	check(not launch.active_rects().is_empty(),"Nodule launch still activates after its warning")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("DEER ROOT WARNINGS")

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var output := "D:/HomingStar/homeing-star-test/artifacts/deer-root-warnings"
	DirAccess.make_dir_recursive_absolute(output)
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
