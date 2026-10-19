extends SceneTree

var checks := 0
var failures := 0
var save: SaveProgressService
var output := ""
const ROOM := "res://scenes/levels/tutorial/tutorial_battle_room.tscn"
const TOWN := "res://scenes/levels/town/homeward_town.tscn"

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func _seed_progress(won: bool) -> void:
	var config := ConfigFile.new()
	# Finished prologue fixtures prevent older tutorials from stealing the dialogue UI.
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			config.set_value("progress", String(value), true)
	config.set_value("progress", String(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), won)
	config.set_value("progress", String(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), false)
	save._config = config
	save._loaded = true

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	_seed_progress(false)
	var room = load(ROOM).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	var boss = room.boss
	var player = room.player
	boss.phase = 2
	room.set_battle_phase(room.BattlePhase.PHASE_2)
	boss._launch_phase_2_ground_wave()
	# Simulate a killing ultimate still restoring Lan; don't freeze it in mid-combo.
	player.set_physics_process(false)
	player.ultimate_active = true
	boss.combat_stats.apply_health_damage(boss.combat_stats.max_health)
	check(save.has_completed(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), "Victory saved immediately before dialogue")
	var persisted := ConfigFile.new()
	persisted.load(SaveProgressService.SAVE_PATH)
	check(persisted.get_value("progress", String(SaveProgressService.STORY_MASTER_PHASE_2_DEFEATED), false), "Victory reached disk before return")
	await process_frame
	await process_frame
	check(room._sendoff_dialogue == null and not player.input_frozen, "Killing ultimate may finish before dialogue")
	check(room.get_children().filter(func(node: Node): return node is MasterGroundWave).is_empty(), "Lingering hostile ground waves removed")
	player.ultimate_active = false
	player.set_physics_process(true)
	await process_frame
	await process_frame
	var dialogue: TutorialDialogue = room._sendoff_dialogue
	check(dialogue != null and dialogue.opened and player.input_frozen, "Victory opens dialogue and freezes movement")
	if dialogue == null:
		quit(1)
		return
	check(dialogue.get_line_progress() == Vector2i(0, 9), "Full M01 contains nine lines")
	check(dialogue._label.text == "行了，过去吧。" and dialogue._cutout == TutorialDialogue.CUTOUT_RIGHT, "Rein opens on right")
	await capture("master_sendoff_right")
	room._on_boss_defeated()
	check(room._sendoff_dialogue == dialogue, "Repeated victory signal does not open duplicate UI")
	dialogue.advance()
	check(dialogue._label.text == "往哪边？" and dialogue._cutout == TutorialDialogue.CUTOUT_LEFT, "Lan answers on left")
	await capture("master_sendoff_left")
	check(not save.has_completed(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), "Sendoff not marked while reading")
	for i in 8: dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), "Completing all lines saves separate sendoff flag")
	var gift: MasterCoreGift = room._core_gift
	check(gift != null and gift.dialogue != null and player.input_frozen, "Sendoff continues into master's item handover")
	await capture("master_gift_right")
	gift.dialogue.advance()
	await capture("master_gift_left")
	var gift_dialogue := gift.dialogue
	for i in 4: gift_dialogue.advance()
	check(save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 1 and gift.reveal != null, "Handover grants one pendant before its reveal")
	check(not save.has_completed(ForestCoreRelic.PRESENTED_ID), "Ownership does not imply completed presentation")
	await capture("master_gift_reveal")
	gift.reveal._finish_reveal()
	check(save.has_completed(ForestCoreRelic.PRESENTED_ID), "Closing reveal records presentation separately")
	check(player.input_frozen, "Player remains frozen through return fade")
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == TOWN, "Completed dialogue returns to town")
	check(absf(current_scene.player.position.x - 3682.0) < 2.0, "Original town return position preserved")
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	check(transition.current_music_path.ends_with("homeward_town_day.mp3"), "Town day music resumes")
	check(current_scene._right_gate_visual.active, "Existing victory still opens town gate")
	await capture("master_sendoff_town")

	# Old victory / interrupted M01: reload the won room, then hear the short town version.
	current_scene.free()
	current_scene = null
	_seed_progress(true)
	check(not save.has_completed(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), "Old save fixture lacks sendoff")
	room = load(ROOM).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	check(room.boss.process_mode == Node.PROCESS_MODE_DISABLED, "Won encounter cannot restart combat")
	await create_timer(3.0).timeout
	check(current_scene.scene_file_path == TOWN, "Old victory returns without another boss fight")
	check(not save.has_completed(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), "Interrupted M01 remains distinguishable from completed M01")
	var town = current_scene
	var master: Node = town.world_root.get_node("Master")
	town.player.position.x = master.position.x - 90
	master.player = town.player
	master.player_in_range = true
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_E
	master._unhandled_input(key)
	gift = master._core_gift
	check(gift != null, "Old victory can recover the unclaimed gift from the town master")
	if gift != null:
		gift_dialogue = gift.dialogue
		for i in 5: gift_dialogue.advance()
		gift.reveal._finish_reveal()
	check(save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 1, "Recovery grants exactly one pendant")
	master._unhandled_input(key)
	dialogue = master._dialogue
	check(dialogue != null and dialogue.get_line_progress() == Vector2i(0, 3), "E on town master opens short three-line reminder")
	if dialogue != null:
		for i in 3: dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_MASTER_SENDOFF_SEEN), "Short reminder completes missing sendoff record")
	check(not town.player.input_frozen and not master.dialogue_open, "Reminder restores movement and interaction")
	print("MASTER SENDOFF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
