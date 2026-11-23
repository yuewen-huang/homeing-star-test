extends "verify_zhenxi_last_lamp.gd"
## Check first viewing, input ownership and retry of the two battle cut-ins.
## Health fixtures isolate the story handoffs. The route regression fights normally.

const Collection := preload("res://scripts/levels/lan_home/home_collection.gd")
const Wave := preload("res://scripts/bosses/sunken_general/sunken_general_wave.gd")


func run() -> void:
	var save := use_memory_progress()
	var folder := "zhenxi-city-final" if "--city-visual" in OS.get_cmdline_user_args() else "zhenxi-battle-comics"
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty():
		output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/" + folder)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(output)
	level = (load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	player = level.player
	level.snap_camera()
	await step(12)
	var gallery := await start_chapter_fight(save)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var previous := assist.difficulty
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.EASY)
	if gallery != null:
		await check_interludes(gallery, save)
	assist.set_difficulty(previous)
	await close_route()


func check_interludes(gallery: Node2D, save: SaveProgressService) -> void:
	var boss: Node2D = gallery.general
	var music := level.get_node("ZhenxiGateMusic") as AudioStreamPlayer
	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	var comic := await wait_for_comic(gallery)
	if comic == null:
		return
	var opened := Engine.get_physics_frames()
	var opened_at := Time.get_ticks_msec()
	check_cards(comic, gallery.ARMOR_COMIC_ID, [&"02_hollow_armor", &"03_fallen_tally"], [0.86, 0.76])
	check(boss.phase == 1 and boss.combat_stats.health == 0 and boss._orders.is_empty()
		and (not is_instance_valid(boss._reinforcements) or boss._reinforcements.is_queued_for_deletion()),
		"The armor cut-in opens after the last phase-one move and reinforcements")
	check(save.get_cinematic_status(comic.cinematic_id) == SaveProgressService.CinematicStatus.UNHANDLED,
		"Opening the first comic leaves its save status pending")
	var at := player.global_position
	var health := player.combat_stats.health
	var playback := music.get_playback_position()
	var wave := make_handoff_wave(boss)
	var wave_start := wave.global_position.x
	Input.action_press(&"ui_right")
	await step(6)
	await capture("09_armor_entering")
	await step(12)
	await check_advance_input(comic, at)
	check_card_placement(comic)
	await capture("10_armor_first")
	while Engine.get_physics_frames() - opened < 60:
		await step(1)
	release()
	check(boss.phase == 1 and player.input_frozen and player.global_position.distance_to(at) < 1.0
		and player.combat_stats.health == health, "Movement and damage stay blocked while the armor cut-in is open")
	check(is_instance_valid(wave) and wave.global_position.x < wave_start - 40.0
		and wave.budget.targets.is_empty(), "A real sword wave keeps moving without spending its contact during the cut-in")
	check_music(music, playback)
	if not await wait_for_second_card(comic):
		return
	await capture("11_armor_last")
	await wait_for_auto_close(comic, opened, opened_at, 2.0)
	check(boss.phase == 2 and boss.combat_stats.health == 880 and not player.input_frozen,
		"The armor cut-in automatically gives phase two its full health and returns control")
	check(save.get_cinematic_status(gallery.ARMOR_COMIC_ID) == SaveProgressService.CinematicStatus.WATCHED,
		"The armor cut-in saves watched after automatically leaving the screen")

	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	comic = await wait_for_comic(gallery)
	if comic == null:
		return
	opened = Engine.get_physics_frames()
	opened_at = Time.get_ticks_msec()
	check_cards(comic, gallery.LAMP_COMIC_ID, [&"03_xiaowu_brings_oil", &"04_banner_projection"], [1.44, 0.88])
	playback = music.get_playback_position()
	await step(23)
	check_card_placement(comic)
	check(boss.phase == 3 and boss.combat_target == null and boss.animated_sprite.visible and player.input_frozen
		and not is_instance_valid(gallery._flag_defense) and not is_instance_valid(player.encounter_arsenal)
		and level.camera.limit_right - level.camera.limit_left == 1280,
		"The lamp cut-in retains the General's pose and keeps the flag, skills and expanded arena pending")
	check_music(music, playback)
	await capture("12_lamp_first")
	if not await wait_for_second_card(comic):
		return
	await capture("13_lamp_last")
	check(save.get_cinematic_status(gallery.LAMP_COMIC_ID) == SaveProgressService.CinematicStatus.UNHANDLED,
		"The last visible card does not write the lamp cut-in yet")
	if "--auto-watch-lamp" in OS.get_cmdline_user_args():
		await wait_for_auto_close(comic, opened, opened_at, 2.7)
		check(save.get_cinematic_status(gallery.LAMP_COMIC_ID) == SaveProgressService.CinematicStatus.WATCHED,
			"The lamp cut-in saves watched after automatically leaving the screen")
	else:
		await tap_key(KEY_ESCAPE)
		for frame in 30:
			if not is_instance_valid(comic): break
			await step(1)
		await step(6)
		check(not is_instance_valid(comic) and save.get_cinematic_status(gallery.LAMP_COMIC_ID) \
			== SaveProgressService.CinematicStatus.SKIPPED and not _settings_open(),
			"Esc skips the lamp cut-in without opening settings and writes the skip independently of victory")
	var defense: Node2D = gallery._flag_defense
	check(is_instance_valid(defense) and defense._state == defense.State.OPEN and defense._assault_age == 0.0
		and defense._wave == 0 and level.camera.limit_right - level.camera.limit_left == 1920,
		"Closing the cut-in begins the original flag entrance with a fresh timer")
	check(not save.has_completed(gallery.VICTORY) and not save.has_claimed_reward(HELMET_FACT),
		"Reading or skipping the comics grants neither victory nor Xiaowu's helmet")
	await step(30)
	if "--city-visual" in OS.get_cmdline_user_args():
		await capture("14a_flag_entry")
	await step(72)
	check(is_instance_valid(defense) and not player.input_frozen and is_instance_valid(player.encounter_arsenal),
		"The ordinary flag entrance hands control back with the borrowed skills")
	await capture("14_flag_opens")
	if "--city-visual" in OS.get_cmdline_user_args():
		Input.action_press(&"ui_left")
		await step(148)
		release()
		await step(25)
		await capture("15_flag_west")
		print("Route-only fixture: injecting victory after the visual flag samples")
		gallery._on_general_defeated()
		await step(14)
		await capture("16_lamp_extinguished")
		await leave_after_victory(gallery, save)
	else:
		await check_retry(gallery)
	var last := Collection.COMICS.size() - 1
	check(Collection.comic_panels(last - 1).size() == 4 and Collection.comic_panels(last).size() == 6,
		"Both chapters can be extracted for read-only replay in Lan's storybook")


func wait_for_comic(gallery: Node2D) -> WindSightingComic:
	for frame in 1800:
		var comic: WindSightingComic = gallery._phase_comic
		if is_instance_valid(comic):
			return comic
		if not is_instance_valid(gallery.general):
			break
		await step(1)
	check(false, "Reached the combat interlude")
	return null


func check_cards(comic: WindSightingComic, id: StringName, names: Array[StringName], holds: Array[float]) -> void:
	var matches := comic.cinematic_id == id and comic.panels.size() == names.size()
	for index in mini(comic.panels.size(), names.size()):
		matches = matches and comic.panels[index].resource_path.get_file().get_basename() == names[index]
	var configured_holds: Variant = comic.get("panel_hold_seconds")
	var same_holds: bool = configured_holds != null and configured_holds.size() == holds.size()
	for index in holds.size():
		if same_holds:
			same_holds = is_equal_approx(float(configured_holds[index]), holds[index])
	check(matches and same_holds, "The two authored cards and their hold times match %s" % id)
	var has_cover := comic.get_children().any(func(child: Node) -> bool:
		return child is ColorRect and child.size.x >= root.get_visible_rect().size.x * 0.95)
	check(not comic.full_screen and not has_cover,
		"The battle view stays visible outside the cut-in card")


func check_advance_input(comic: WindSightingComic, at: Vector2) -> void:
	for key in [KEY_E, KEY_SPACE, KEY_ENTER]:
		await tap_key(key)
	check(is_instance_valid(comic) and comic.panel_index == 0 and player.input_frozen
		and player.global_position.distance_to(at) < 1.0,
		"E, Space and Enter leave the first card and frozen Lan in place")


func check_card_placement(comic: WindSightingComic) -> void:
	var size := root.get_visible_rect().size
	var art := comic.get("_card") as Control
	if art == null:
		check(false, "The battle cut-in uses a framed side card")
		return
	var center := art.global_position + art.size * 0.5
	var on_side := center.x > size.x * 0.60 if comic.get("enter_from_right") else center.x < size.x * 0.40
	check(on_side and absf(art.rotation) > 0.02 and center.y > 0.0 and center.y < size.y
		and art.size.x < size.x * 0.5 and art.global_position.y + art.size.y < size.y * 0.60,
		"The angled card settles at an upper edge of the live arena (%s, %s, %.1f degrees in %s)"
		% [art.global_position, art.size, rad_to_deg(art.rotation), size])


func wait_for_second_card(comic: WindSightingComic) -> bool:
	for frame in 135:
		if not is_instance_valid(comic): break
		var art := comic.get("_card") as Control
		if comic.panel_index == 1 and art != null and art.modulate.a >= 0.90:
			check(comic._image.texture == comic.panels[1], "The second card appears without another input")
			return true
		await step(1)
	check(false, "Reached the second cut-in card")
	return false


func wait_for_auto_close(comic: WindSightingComic, opened: int, opened_at: int, expected: float) -> void:
	for frame in 210:
		if not is_instance_valid(comic): break
		await step(1)
	var seconds := (Engine.get_physics_frames() - opened) / 60.0
	var wall_seconds := (Time.get_ticks_msec() - opened_at) / 1000.0
	print("Battle cut-in %.2f physics seconds, %.2f wall seconds" % [seconds, wall_seconds])
	check(not is_instance_valid(comic) and absf(seconds - expected) < 0.50,
		"The cut-in automatically closes in its short playback window")
	await step(6)


func _settings_open() -> bool:
	var settings := root.get_node_or_null("AudioSettings") as AudioSettingsService
	return settings != null and is_instance_valid(settings.settings_panel) and settings.settings_panel.visible


func make_handoff_wave(boss: Node2D) -> Wave:
	var wave := Wave.new()
	wave.slow_wave = true
	wave.world_min_x = boss.world_min_x - 56.0
	wave.world_max_x = boss.world_max_x + 56.0
	boss.add_child(wave)
	wave.top_level = true
	var attack := CombatAttackData.new(&"zhenxi_comic_wave_probe", boss, 8, 0, 0.0, 0.0)
	wave.launch(player.global_position + Vector2(72.0, 0.0), -1.0, 260.0, 120.0, attack, {"targets": {}})
	boss.waves.append(wave)
	wave.spent.connect(func() -> void: boss.waves.erase(wave))
	return wave


func check_music(music: AudioStreamPlayer, playback: float) -> void:
	var advancing := DisplayServer.get_name() == "headless" or music.get_playback_position() > playback + 0.2
	check(music.playing and not music.stream_paused and advancing,
		"The same gallery track continues through the comic")


func check_retry(gallery: Node2D) -> void:
	level._retry_hidden_battle()
	await step(8)
	check(not is_instance_valid(gallery._phase_comic) and not player.input_frozen,
		"Retry clears the previous handoff and releases control")
	var layout := gallery.get_node("ChapterLayout") as Node2D
	if not await walk_to_mark(layout, "LampInspect") or not await interact_at_lamp(gallery, false):
		return
	var boss: Node2D = gallery.general
	var comic_reopened := false
	for starting_phase in [1, 2]:
		# The first fight already exercised the real reinforcement queues.
		boss._threshold_index = boss.THRESHOLDS.size()
		boss.combat_stats.apply_health_damage(boss.combat_stats.health)
		for frame in 720:
			comic_reopened = comic_reopened or is_instance_valid(gallery._phase_comic)
			if not is_instance_valid(boss) or boss.phase != starting_phase or comic_reopened:
				break
			await step(1)
		if not is_instance_valid(boss) or comic_reopened:
			break
	check(not comic_reopened and is_instance_valid(gallery._flag_defense),
		"Already handled cut-ins bypass playback on a second attempt")


func close_route() -> void:
	release()
	var music := level.get_node_or_null("ZhenxiGateMusic") as AudioStreamPlayer
	if music != null:
		music.stop()
		music.stream = null
	level.queue_free()
	await wait_frames(5)
	expect_save_untouched()
	finish("ZHENXI BATTLE COMICS")
