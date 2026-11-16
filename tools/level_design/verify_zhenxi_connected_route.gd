extends "../../tests/levels/chapter_2_underwater/cavern/test_zhenxi_general_route.gd"
## Exercises the real arch, the new approach, the existing battle, and the dry A18 arrival.

func run() -> void:
	var save := use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var difficulty := assist.difficulty
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/zhenxi-connected-route")
	DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	player.reset_after_map_fall(level.marker("pool_bank"))
	level.snap_camera()
	await step(12)
	if "--legacy-victory" in OS.get_cmdline_user_args():
		await check_legacy_visit(save)
	elif "--layout-only" in OS.get_cmdline_user_args():
		var gallery := await start_fight_from_a18(save)
		if gallery != null:
			gallery._on_general_defeated()
			gallery.place_at_victory_return()
			await step(12)
			await leave_after_victory(gallery, save)
	else:
		await check_route(save)
	check(level.drowned_count == 0, "The connected route needs no drowning or map-fall reset")
	assist.set_difficulty(difficulty)
	await end_test()


func start_fight_from_a18(save: SaveProgressService) -> Node2D:
	await interact()
	check(not level._inside_gallery, "The real A18 dry bank is outside the hidden arch")
	if not await swim_to_arch():
		check(false, "Lan can dive from the A18 bank to the hidden arch")
		return null
	await interact()
	await step(35)
	var section: ZhenxiSluiceSection = level.sluice
	var entered := is_instance_valid(section) and section.lan == player and player.is_in_deep_water()
	check(entered and section.camera.is_current(), "The arch brings the same Lan to the flooded end of the new route")
	if not entered:
		return null
	await capture("02_arch_into_sluice")

	await interact()
	await step(35)
	check(not level._inside_gallery and not is_instance_valid(level.sluice) and player.is_in_deep_water(),
		"Retreating through the entrance restores the original submerged arch and camera")
	check(level.camera.is_current() and not save.has_completed(level._hidden_gallery.CHAPTER_VICTORY),
		"Retreating leaves the original route available without setting victory")
	if level._inside_gallery or not await swim_to(Vector2(9472, 3435), "swim"):
		check(false, "Lan can approach the arch again after retreating")
		return null
	await interact()
	await step(35)
	section = level.sluice
	check(is_instance_valid(section) and section.lan == player, "Reentering opens a fresh approach with the same player")
	if not is_instance_valid(section):
		return null
	var pool := section.player_rect(ZhenxiSluiceSection.POOL)
	var track := level.get_node("ZhenxiGateMusic") as AudioStreamPlayer
	var stream := track.stream
	if not await cross_sluice(section):
		return null
	check(level._inside_gallery and level.sluice == null and level.player == player and level.camera.is_current(),
		"The rear cut places the same Lan on the production court and hands the camera back")
	check(track.playing and track.stream == stream, "The onward cut keeps the gallery theme playing")
	check(not player.swim.zones.has(pool), "The temporary water volume is unregistered when the section closes")
	if is_instance_valid(level.sluice):
		return null

	var gallery: Node2D = level._hidden_gallery
	var layout := gallery.get_node("ChapterLayout") as Node2D
	check(not level._can_use_hidden_door() and not save.has_completed(gallery.CHAPTER_VICTORY),
		"The onward cut neither unlocks the return nor records victory")
	if not await walk_to_mark(layout, "LampInspect"):
		return null
	await capture("05_lamp_approach")
	return gallery if await interact_at_lamp(gallery, true) else null


func leave_after_victory(gallery: Node2D, save: SaveProgressService) -> void:
	var layout := gallery.get_node("ChapterLayout") as Node2D
	var view := gallery.get_node("PostBattleView") as CanvasLayer
	check(gallery.won and save.has_completed(gallery.CHAPTER_VICTORY), "The production defense unlocks the short return")
	check(not save.has_claimed_reward(HELMET_FACT) and not save.has_completed(gallery.ARCHIVE_READ),
		"Victory leaves the optional helmet and archive untouched")
	if not await walk_to_mark(layout, "StoryHelmet"):
		return
	await interact()
	check(view.visible and save.get_item_count(HELMET_FACT) == 1, "The helmet still opens its inspection and grants the unique item")
	await interact()
	if not await walk_to_mark(layout, "Archive"):
		return
	await interact()
	check(view.visible and view.archive_page == 0 and not save.has_completed(gallery.ARCHIVE_READ),
		"The relocated archive opens on page one without counting as read")
	await interact()
	check(view.visible and view.archive_page == 1 and save.has_completed(gallery.ARCHIVE_READ),
		"The second page still records the archive read")
	await interact()
	await capture("06_archive_on_the_return")
	check(not level._can_use_hidden_door(), "Reading the archive is outside the main gate's interaction range")

	var departure: Marker2D = level._gallery_exit
	var gate := level.to_local(departure.global_position)
	if not await walk_plain(gate):
		check(false, "The victory path reaches the main gate from the archive")
		return
	await capture("06_main_gate")
	Input.action_press(&"ui_right")
	await step(43)
	release()
	check(absf(player.position.y - gate.y) < 4.0 and standing(),
		"Following the courtyard through the gate stays on the same floor at the far jamb")
	check(level._can_use_hidden_door(), "Lan can still use the main gate from the far jamb")
	await interact()
	await resolve_passage(level.DEPARTURE_COMIC_ID)
	var bank: Vector2 = level.marker("pool_bank")
	check(not level._inside_gallery and level.player == player and not player.is_in_deep_water()
		and player.position.distance_to(bank) < 24.0, "The completed route returns the same Lan directly to the A18 dry bank")
	var track := level.get_node("ZhenxiGateMusic") as AudioStreamPlayer
	check(not track.playing, "The gallery theme releases on the A18 bank")
	await capture("07_back_on_a18")
	if level._inside_gallery:
		return

	if not await swim_to_arch():
		check(false, "The arch is still reachable after the completed visit")
		return
	await interact()
	await step(35)
	check(level._inside_gallery and level.sluice == null and gallery.won and not is_instance_valid(gallery.general),
		"A post-victory revisit goes directly to the lamp and does not replay the approach or combat")
	check(save.get_item_count(HELMET_FACT) == 1 and save.has_completed(gallery.ARCHIVE_READ),
		"Revisiting preserves the helmet and archive without duplicating them")


func resolve_passage(id: StringName) -> void:
	var comic: WindSightingComic
	for frame in 180:
		comic = level._passage_comic
		if comic != null and not comic.get("covered_by_fade"):
			break
		await step(1)
	var ready: bool = is_instance_valid(comic) and not comic.get("covered_by_fade")
	check(ready, "The first visit opens the cinematic %s" % id)
	if not ready:
		return
	var progress := root.get_node("SaveProgress") as SaveProgressService
	var pending := SaveProgressService.CinematicStatus.UNHANDLED
	var track := level.get_node("ZhenxiGateMusic") as AudioStreamPlayer
	check(comic.cinematic_id == id and comic.panel_index == 0 and comic.panels.size() == 2,
		"The correct two-panel comic starts on its first panel")
	check(progress.get_cinematic_status(id) == pending and not player.is_physics_processing()
		and not level.oxygen.is_physics_processing() and track.playing,
		"The active transition freezes Lan and oxygen and continues the gallery track")
	await capture(String(id) + "_01")
	var skipped := "--skip-passage" in OS.get_cmdline_user_args()
	if skipped:
		await tap_key(KEY_ESCAPE)
	else:
		await tap_key(KEY_E)
		await step(17)
		check(comic.panel_index == 1 and progress.get_cinematic_status(id) == pending,
			"Advancing to the second drawing leaves completion pending")
		await capture(String(id) + "_02")
		await tap_key(KEY_E)
	await step(36)
	var status := SaveProgressService.CinematicStatus.SKIPPED if skipped else SaveProgressService.CinematicStatus.WATCHED
	check(level._passage_comic == null and progress.get_cinematic_status(id) == status,
		"Completing the passage records its own watched or skipped status")
	check(player.is_physics_processing() and level.oxygen.is_physics_processing() and not level._crossing_door,
		"The transition gives back movement only after the world fade")


func check_legacy_visit(save: SaveProgressService) -> void:
	save.try_complete_fact(&"zhenxi_last_lamp_chapter_defended")
	if not await swim_to_arch():
		check(false, "The legacy save can reach the original arch")
		return
	await interact()
	await step(35)
	var gallery: Node2D = level._hidden_gallery
	check(gallery != null and gallery.won and level.sluice == null and level._passage_comic == null,
		"An existing victory enters the restored court without forcing the new approach")
	if gallery == null or not await walk_to_mark(gallery.get_node("ChapterLayout"), "ReturnDoor"):
		return
	await interact()
	await step(35)
	check(not level._inside_gallery and player.position.distance_to(level.marker("pool_bank")) < 24.0,
		"The existing victory can use the new short return")
	for id: StringName in [level.ARRIVAL_COMIC_ID, level.DEPARTURE_COMIC_ID]:
		check(save.get_cinematic_status(id) == SaveProgressService.CinematicStatus.UNHANDLED,
			"Loading or departing on the old save does not claim to have played %s" % id)


func swim_to_arch() -> bool:
	return await swim_to(Vector2(8960, 2880), "swim") \
		and await swim_to(Vector2(9088, 3328), "swim") \
		and await swim_to(Vector2(9472, 3435), "swim")
