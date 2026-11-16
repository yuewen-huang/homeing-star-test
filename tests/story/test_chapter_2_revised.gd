extends "../support/harness.gd"

const Text := preload("res://scripts/story/chapter_2_dialogue.gd")
const SaltStory := preload("res://scripts/levels/chapter_2_salt/salt_field_story.gd")
const Crab := preload("res://scripts/levels/chapter_2_salt/salt_field_crab_encounter.gd")
const LakeStory := preload("res://scripts/levels/mirror_lake/mirror_lake_chapter_story.gd")
const CavernStory := preload("res://scripts/levels/chapter_2_underwater/cavern/sunken_cavern_chapter_story.gd")
const SALT := "res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn"
var save: MemoryProgress
var transition: SceneTransitionService

func run() -> void:
	save = use_memory_progress()
	transition = root.get_node("SceneTransition") as SceneTransitionService
	await salt()
	if current_scene is MirrorLake:
		await lake()
	if current_scene is SunkenCavern:
		await cavern()
	expect_save_untouched()
	finish("CHAPTER TWO REVISED STORY")

func salt() -> void:
	transition.set_scene_entry_anchor(^"Entry")
	save._config.set_value("map_states", "chapter_2_salt_field", {"boss_pile": 1, "dug": []})
	check(change_scene_to_file(SALT) == OK, "The salt field loads")
	await scene_changed
	await wait_frames(3)
	var field := current_scene as Chapter2SaltField
	await read(field.salt_story.beat.dialogue, Text.SALT_ENTRY, "salt_arrival")
	check(save.has_completed(SaltStory.ENTRY_READ), "Only finishing both lines settles the opening")
	check(not field.has_node("Shibo"), "The retired anomaly narrative does not spawn")
	for point in SaltStory.POINTS:
		field.feet = point[1]
		field._sync_view(0)
		await wait_frames(2)
		press(KEY_E)
		await read(field.salt_story.beat.dialogue, point[2], str(point[0]).to_snake_case())
	field.feet = field.piles[1].ground_position + Vector2(0, 42)
	field._sync_view(0)
	field.target = 1
	field._finish_dig()
	var encounter = field.crab_encounter
	for frame in 150:
		await physics_frame
		if encounter._warning.dialogue != null: break
	check(encounter.active and encounter.crab.manual_control, "The crystal crab stays held before the warning")
	await read(encounter._warning.dialogue, Text.CRAB_WARNING, "crab_warning")
	check(encounter.active and not encounter.crab.manual_control and not paused, "The first battle starts after the warning")
	# Skip the unchanged fight damage loop, then use its actual win and departure handoff.
	encounter.crab.become_peaceful()
	encounter._finish_victory()
	for frame in 400:
		await process_frame
		if encounter.dialogue != null: break
	await read(encounter.dialogue, Text.CRAB_TRAVEL, "crab_travel")
	await wait_frames(3)
	check(encounter.comic != null, "The existing crab ride follows the new farewell")
	press(KEY_ESCAPE)
	await wait_for(SALT)
	field = current_scene as Chapter2SaltField
	field.feet = Crab.CAVE_FEET
	field._sync_view(0)
	await wait_frames(3)
	press(KEY_E)
	await read(field.crab_encounter.dialogue, Text.SCROLL, "salt_scroll")
	press(KEY_ESCAPE)
	await wait_for(Crab.MIRROR_LAKE)
	check(current_scene is MirrorLake, "The scroll leads to the real mirror lake")

func lake() -> void:
	var map := current_scene as MirrorLake
	await read(map.chapter_story.beat.dialogue, Text.LAKE_ENTRY, "lake_arrival")
	check(map.request_switch() and map.controls_inverted(), "The real yin switch still inverts the direction")
	Input.action_press(&"ui_left")
	await wait_frames(15)
	Input.action_release(&"ui_left")
	check(map.chapter_story._bubble_line == Text.LAKE_INVERTED[0][1], "Moving after the yin switch triggers the authored reaction")
	map.player.position = Vector2(PandaGoArena.TRIGGER_X + 30.0, MirrorLake.STAND_Y)
	await wait_frames(3)
	check(not map.panda_arena.active, "Xuanbai waits while the prebattle dialogue is open")
	await read(map.chapter_story.beat.dialogue, Text.PANDA_INTRO, "xuanbai_intro")
	check(map.panda_arena.active, "The existing encounter begins when the dialogue finishes")
	# Settle existing combat in place to exercise the actual restored exploration and exit.
	map.panda_arena._finish_victory()
	map.player.position = Vector2(LakeStory.EXIT_X, MirrorLake.STAND_Y)
	await wait_frames(3)
	press(KEY_E)
	await read(map.chapter_story.beat.dialogue, Text.PANDA_DEPARTURE, "xuanbai_departure")
	var comic := map.chapter_story._ink_fish_comic as WindSightingComic
	check(comic != null, "The finished farewell opens the ink fish comic")
	if comic == null: return
	check(comic.panels.size() == 3 and comic.panel_index == 0, "The comic opens on the brush panel")
	check(paused and map.player.input_frozen and comic.layer < transition.layer, "The comic locks exploration below the scene fade")
	check(save.has_completed(LakeStory.DEPARTURE), "The finished conversation has its own record")
	check(save.get_cinematic_status(LakeStory.INK_FISH) == SaveProgressService.CinematicStatus.UNHANDLED,
		"Opening the comic does not record a viewing")
	check(not save.has_completed(CavernStory.ROUTE), "The player has not arrived in the cavern")
	var music := transition.current_music_path
	await capture("ink_fish_01_brush")
	press(KEY_E)
	press(KEY_E)
	check(comic.panel_index == 1, "A rapid second press cannot skip the fish reveal")
	await create_timer(0.26).timeout
	await capture("ink_fish_02_lift")
	press(KEY_E)
	await create_timer(0.26).timeout
	check(comic.panel_index == 2 and transition.current_music_path == music,
		"The descent panel still uses the Mirror Lake track")
	await capture("ink_fish_03_descent")
	press(KEY_E)
	check(transition.is_transitioning and is_instance_valid(comic), "The last panel stays under the outgoing fade")
	check(save.get_cinematic_status(LakeStory.INK_FISH) == SaveProgressService.CinematicStatus.WATCHED,
		"Reading all three panels records a completed viewing")
	check(not save.has_completed(CavernStory.ROUTE), "Viewing and arrival are separate")
	await wait_for(LakeStory.CAVERN)
	check(current_scene is SunkenCavern, "The new passage reaches the real sunken cavern")
	check(not paused and not current_scene.player.input_frozen and save.has_completed(CavernStory.ROUTE),
		"Arrival records the route and restores movement")
	await capture("ink_fish_04_arrival")

func cavern() -> void:
	var map := current_scene as SunkenCavern
	var story = map.chapter_story
	check(story != null and map.resonance.echoes.size() == 4, "The story route installs all four bell echoes")
	if story == null: return
	map.resonance._on_bell_struck()
	await wait_frames(3)
	await read(story.beat.dialogue, Text.CAVERN_ENTRY, "cavern_bell")
	await stand_at(map, story._gate_prompt.target.position)
	press(KEY_E)
	await read(story.beat.dialogue, Text.CICADA_LOCKED, "cicada_locked")
	check(not save.has_completed(CavernStory.PASSAGE) and not story._gate.get_child(0).disabled, "Cicada physically bars the hall on missing echoes")
	check(save.try_complete_fact(map.resonance.WALL_BROKEN), "Fixture restores the wall puzzle before testing its follow-on")
	map.stone_lion._wall_shape.disabled = true
	map.stone_lion.broken = true
	map.resonance.awake = true
	for id: String in CavernStory.ECHO_ROWS:
		var target: Vector2 = map.resonance.echoes[id]
		await stand_at(map, target + Vector2(0.0, 31.0))
		map.resonance._on_echo_arrived(id)
		await wait_frames(4)
		await read(story.beat.dialogue, CavernStory.ECHO_ROWS[id], "echo_" + id)
		check(map.resonance.collected.has(id) and save.has_completed(story._heard_fact(id)), "Collected and heard " + id)
	await stand_at(map, story._memory_prompt.target.position)
	press(KEY_E)
	await read(story.beat.dialogue, Text.GENERAL_MEMORY, "general_memory")
	check(save.has_completed(CavernStory.GENERAL), "The optional general memory can be read at its existing branch")
	await stand_at(map, story._gate_prompt.target.position)
	press(KEY_E)
	await read(story.beat.dialogue, Text.CICADA_OPEN, "cicada_open")
	await wait_frames(3)
	check(save.has_completed(CavernStory.PASSAGE) and story._gate.get_child(0).disabled, "All four readings open the actual passage")
	await stand_at(map, map.vector(map.layout.markers.boss))
	await read(story.beat.dialogue, Text.FISH_PREBATTLE, "fish_prebattle")
	check(save.has_completed(CavernStory.FISH) and not paused and map.player.can_process(), "The chapter ends its revised story at prebattle with controls restored")

func stand_at(map: SunkenCavern, at: Vector2) -> void:
	map.player.reset_after_map_fall(at)
	map.snap_camera()
	await wait_frames(3)

func wait_for(path: String) -> void:
	for tick in 250:
		if current_scene != null and current_scene.scene_file_path == path and not transition.is_transitioning:
			await wait_frames(3)
			return
		await create_timer(0.02).timeout
	check(false, "Expected route " + path)

func read(dialogue: TutorialDialogue, rows: Array, label: String) -> void:
	if dialogue == null:
		check(false, "Missing dialogue " + label)
		return
	for index in rows.size():
		check(dialogue._label.text == rows[index][1] and paused, "%s line %s matches the revised script" % [label, index])
		press(KEY_E)
		await process_frame
		if index == 0:
			if dialogue._label.visible_characters != rows[index][1].length():
				check(false, "The first E reveals the rest of the line")
			await capture(label)
		press(KEY_E)
		await process_frame

func press(code: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = true
	root.push_input(key)
	var release := key.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release)

func capture(label: String) -> void:
	var out := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if out.is_empty() or DisplayServer.get_name() == "headless": return
	await create_timer(0.20).timeout
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(out.path_join(label + ".png")) == OK, "Captured " + label)
