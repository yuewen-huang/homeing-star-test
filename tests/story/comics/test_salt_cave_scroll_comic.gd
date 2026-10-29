extends SceneTree
## Real cave interaction -> common comic -> Mirror Lake, using memory-only progress.
class MemorySave extends SaveProgressService:
	var fail_write := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_write
	func is_ability_unlocked(_ability: StringName) -> bool: return true

const FIELD := "res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn"
const COMIC_ID := &"salt_cave_scroll_to_mirror_lake"
const FRAME_NAMES := ["01_scroll_discovery", "02_touch", "03_absorption", "04_arrival", "05_look_up", "06_ink_world"]
var save: MemorySave
var field: Chapter2SaltField
var transition: SceneTransitionService
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label_: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label_)

func press(key: Key = KEY_E, echo := false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = key
	event.keycode = key
	event.echo = echo
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	root.push_input(event)

func enter() -> void:
	field = load(FIELD).instantiate() as Chapter2SaltField
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
	field.feet = field.crab_encounter.CAVE_FEET
	field.crab_encounter.step(1.0 / 60)
	field._sync_view(0)

func clear_scene() -> void:
	if is_instance_valid(current_scene): current_scene.free()
	current_scene = null
	field = null

func wait_for_fade() -> void:
	for i in 100:
		await create_timer(0.05).timeout
		if not transition.is_transitioning: return
	check(false, "Real map fade finishes within five seconds")

func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_ + ".png")) == OK, "Capture " + label_)

func status() -> SaveProgressService.CinematicStatus:
	return save.get_cinematic_status(COMIC_ID)

func run() -> void:
	seed(20261029)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	save._config.set_value("progress", "chapter_2_salt_crab_defeated", true)
	save._config.set_value("cinematics", "salt_to_mirror_lake", SaveProgressService.CinematicStatus.WATCHED)
	save._config.set_value("map_states", "chapter_2_salt_field", {"boss_pile": 1, "dug": [1]})
	transition = root.get_node("SceneTransition") as SceneTransitionService
	enter()
	check(field.crab_encounter.can_use_exit(), "Existing unlocked cave remains the entry point")
	var original_music := transition.music_player.stream
	await create_timer(0.2).timeout
	var original_position := transition.music_player.get_playback_position()
	press()
	var encounter = field.crab_encounter
	var comic: WindSightingComic = encounter.comic
	check(comic != null and comic.panel_index == 0, "Real E opens frame zero without entry-key passthrough")
	check(comic is ComicPlayer and comic.get_script().resource_path == "res://scripts/story/comics/wind_sighting_comic.gd", "Existing WindSightingComic owns playback")
	check(comic._frames.size() == 6 and comic.cinematic_id == COMIC_ID, "Six frames have an independent viewing record")
	check(paused and field.pawn.player.input_frozen and not field.hud.visible, "Reading pauses exploration and hides its HUD")
	check(comic.layer == 900 and comic.layer < transition.layer, "Comic covers gameplay HUD below the shared fade")
	check(comic._image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and comic._image.offset_bottom == -ComicPlayer.IMAGE_BOTTOM_MARGIN, "Shared view preserves proportions and reserves its hint strip")
	press(KEY_E, true)
	check(comic.panel_index == 0, "Held key echo cannot skip the opening frame")
	transition.is_transitioning = true
	press(KEY_ENTER)
	press(KEY_ESCAPE)
	check(comic.panel_index == 0 and status() == SaveProgressService.CinematicStatus.UNHANDLED, "Incoming fade blocks advancement and skip")
	transition.is_transitioning = false
	for i in 6:
		check(comic.panel_index == i and comic._frames[i].resource_path.get_file().get_basename() == FRAME_NAMES[i], "Reading order: " + FRAME_NAMES[i])
		check(comic._image.modulate == Color.WHITE, "Artwork retains its full original colors")
		await capture("salt_scroll_%02d" % (i + 1))
		if i < 5:
			press(KEY_SPACE if i % 2 == 0 else KEY_ENTER)
			press()
			check(comic.panel_index == i + 1, "Rapid second input cannot skip a fading panel")
			await create_timer(0.25).timeout
	check(transition.current_music_path == Chapter2Music.SALT_FIELD.resource_path and transition.music_player.stream == original_music and transition.music_player.get_playback_position() >= original_position, "Comic preserves salt-field BGM and playback position")
	check(not save.has_completed(&"mirror_lake_entered"), "Reading does not prewrite destination arrival")
	save.fail_write = true
	press()
	check(comic._pending_completion_retry and status() == SaveProgressService.CinematicStatus.UNHANDLED and not transition.is_transitioning, "Failed viewing stays retryable without transition")
	await capture("salt_scroll_save_retry")
	press(KEY_ESCAPE)
	await process_frame
	check(not paused and not encounter.session_active and not field.pawn.player.input_frozen and field.hud.visible, "Abandon restores pause, movement and HUD")
	check(status() == SaveProgressService.CinematicStatus.UNHANDLED and encounter.comic == null, "Abandon never claims watching or skipping")
	save.fail_write = false
	encounter.step(1.0 / 60)
	press()
	check(encounter.comic != null and encounter.comic.panel_index == 0, "Fresh cave interaction retries an abandoned comic")
	clear_scene()
	await process_frame
	check(not paused and status() == SaveProgressService.CinematicStatus.UNHANDLED, "Teardown restores pause without false completion")
	enter()
	press()
	comic = field.crab_encounter.comic
	comic._show_panel(5, false)
	save.fail_write = true
	press()
	check(comic._pending_completion_retry and not transition.is_transitioning, "Completion waits for persistence")
	save.fail_write = false
	press()
	check(status() == SaveProgressService.CinematicStatus.WATCHED and transition.is_transitioning and comic.visible, "Retry records watched and retains final panel under fade")
	press()
	press(KEY_ESCAPE)
	check(status() == SaveProgressService.CinematicStatus.WATCHED and not save.has_completed(&"mirror_lake_entered"), "Final repeated input cannot change outcome or prewrite arrival")
	check(not (root.get_node("AudioSettings") as AudioSettingsService).settings_panel.visible, "Repeated final Esc cannot leak into global settings")
	await wait_for_fade()
	var lake := current_scene as MirrorLake
	check(lake != null and not paused and not (lake.player as LanPlayer).input_frozen, "Real transition restores controllable Mirror Lake")
	check(not (root.get_node("AudioSettings") as AudioSettingsService).settings_panel.visible, "Arrival is not covered by an input-leaked settings menu")
	check(save.has_completed(&"mirror_lake_entered") and not lake._arrival_pending, "Destination records successful arrival")
	check(lake.side == MirrorLake.Side.YANG and is_equal_approx(lake.player.position.x, MirrorLake.SPAWN_X) and not lake.entry.seal_activated, "Arrival preserves the ordinary entrance and unsolved seal")
	check(transition.current_music_path == MirrorLakeMusic.EXPLORE.resource_path, "Music changes at the actual lake boundary")
	await capture("salt_scroll_mirror_lake_arrival")
	clear_scene()
	enter()
	press()
	check(transition.is_transitioning and not field.crab_encounter.session_active and field.crab_encounter.comic == null, "Watched revisit enters directly without forced replay")
	await wait_for_fade()
	clear_scene()
	save._config.set_value("cinematics", String(COMIC_ID), SaveProgressService.CinematicStatus.UNHANDLED)
	enter()
	press()
	comic = field.crab_encounter.comic
	check(comic != null and comic.panel_index == 0, "Older lake arrival can still view the new comic once")
	save.fail_write = true
	press(KEY_ESCAPE)
	check(comic._pending_completion_retry and status() == SaveProgressService.CinematicStatus.UNHANDLED and not transition.is_transitioning, "Failed skip waits for persistence")
	save.fail_write = false
	press()
	check(status() == SaveProgressService.CinematicStatus.SKIPPED and transition.is_transitioning, "Skip retry preserves SKIPPED rather than WATCHED")
	await wait_for_fade()
	clear_scene()
	enter()
	press()
	check(transition.is_transitioning and field.crab_encounter.comic == null, "Skipped revisit also avoids forced replay")
	await wait_for_fade()
	clear_scene()
	check(not paused, "All story exits restore tree pause")
	print("SALT CAVE SCROLL COMIC: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
