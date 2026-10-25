extends SceneTree
class FailedSave extends SaveProgressService:
	var failing := true
	func save_progress() -> bool: return not failing
const ROOM := "res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn"
var save: SaveProgressService
var room: Chapter1DeerBossRoom
var story: DeerStory
var boss: DeerBoss
var checks := 0
var failures := 0
var output := ""
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)
func seed_progress() -> void:
	save._config = ConfigFile.new()
	save._loaded = true
	for value: Variant in save.get_script().get_script_constant_map().values():
		if value is StringName and (String(value).begins_with("story_") or String(value).begins_with("tutorial_") or String(value).begins_with("quest_")):
			save._config.set_value("progress", String(value), not (String(value).begins_with("story_c1_") or String(value).begins_with("quest_c1_")))
	save.progress_changed.emit()
func clear_scene() -> void:
	if current_scene != null: current_scene.free()
	current_scene = null
func fixture_intro(empty := false) -> PackedScene:
	var comic := load("res://scripts/story/comics/deer_intro_comic.gd").new() as WindSightingComic
	var texture := GradientTexture2D.new()
	texture.gradient = Gradient.new()
	if not empty: comic.panels.append(texture)
	var packed := PackedScene.new()
	packed.pack(comic)
	comic.free()
	return packed
func enter(intro: PackedScene = null) -> void:
	room = load(ROOM).instantiate() as Chapter1DeerBossRoom
	if intro != null: room.deer_intro_scene = intro
	root.add_child(room)
	current_scene = room
	story = room.story
	boss = room.deer
	await process_frame
	await process_frame
func key(code: Key = KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
func stand(at: Vector2) -> void:
	room.player.position = at
	room.player.velocity = Vector2.ZERO
	room.player.air_state = LanPlayer.AirState.GROUNDED
	room._process(0)
	(room.get_node("Camera2D") as Camera2D).reset_smoothing()
	await create_timer(0.15).timeout
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)
func prepare_human() -> void:
	boss.phase = 4
	boss.reset_phase()
	boss.set_physics_process(false)
	for i in 900:
		boss._physics_process(1.0 / 60)
		if boss.vine_phase.human and boss.vine_phase.step == DeerVinePhase.Step.HOVER: break
	check(boss.vine_phase.human and boss.vine_phase.step == DeerVinePhase.Step.HOVER, "Actual authored transformation reaches human hover")
func kill_human() -> void:
	var already_won := save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED)
	boss.combat_stats.apply_health_damage(boss.combat_stats.health)
	check(boss.state == DeerBoss.State.PHASE_END and save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) == already_won, "Lethal hit before final landing preserves previous victory state")
	for i in 400:
		boss._physics_process(1.0 / 60)
		if boss.state == DeerBoss.State.COMPLETE: break
	await process_frame
func dismiss_reward() -> void:
	if story.reward_reveal != null:
		story.reward_reveal._finish_reveal()
		await process_frame
func run() -> void:
	save = root.get_node("SaveProgress") as SaveProgressService
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	seed_progress()
	await enter(fixture_intro(true))
	check(story.comic == null and not paused and boss.is_physics_processing(), "Missing M09 art allows immediate production battle without placeholder")
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_ENCOUNTERED) and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == 0, "Battle attempt is independent of comic handling")
	check(story.resident == null and not story.body_prompt.available and not story.trace_prompt.available, "No resident or post-battle interactions during live fight")
	for phase in [1, 2, 3, 4]: room._on_phase_completed(phase)
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Signals without actual final human completion cannot fake victory")
	# M10 short reactions use only production facts and never pause combat.
	boss.set_physics_process(false)
	boss.phase = 2
	# Isolate this optional reaction from the direct-route save's locked core powers.
	boss.manual_control = true
	boss.root_phase.item_available = true
	boss.root_phase.start_ultimate()
	boss.root_phase.elapsed = 1.5
	check(boss.root_phase.use_decoy(), "Production root counter accepts a valid decoy")
	story._process(0.8)
	check(story._said.has(&"decoy") and not paused, "Successful decoy queues only a nonblocking bubble")
	boss.root_phase.reset_all()
	boss.manual_control = false
	story._pending_bubble = ""
	story._queue_bubble(&"capture", "过去了！")
	boss.warning_kind = &""
	boss._change_state(DeerBoss.State.IDLE)
	story._process(0.8)
	await capture("deer_combat_bubble")
	check(story._bubble != null and story._bubble.visible and not room.player.input_frozen, "Battle bubble leaves movement and fight clock alone")
	await prepare_human()
	story._process(0)
	check(story._said.has(&"human"), "Actual human transformation enables its single short reaction")
	var inventory := save.get_inventory_items().duplicate(true)
	boss.vine_phase.spawn_strike(&"curtain", room.player.position.x, room.player.position.x - 200, 1)
	await kill_human()
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and not story.victory_pending, "Final production landing saves victory before any inspection")
	check(story.reward_reveal != null and save.get_item_count(ItemCatalog.DEER_RELIC) == 1 and not story.chapter_gate.visible, "Final landing grants exactly one relic and presents it before unlocking portal")
	await dismiss_reward()
	check(story.chapter_gate.visible and not paused, "Closing reward presentation reveals chapter two portal and resumes play")
	inventory[ItemCatalog.DEER_RELIC] = 1
	save.load_progress()
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Victory reloads from disk")
	check(boss.state == DeerBoss.State.COMPLETE and not boss.visible and not boss.is_physics_processing() and story.resident != null, "Persisted victory replaces completed combat body with permanent resident")
	check(not boss.is_in_group("damageable") and (boss.get_node("Hurtbox") as Area2D).collision_layer == 0, "Resident has no lingering combat target or hurtbox")
	check(boss.vine_phase.strikes.is_empty() and boss.root_phase.nodules.is_empty() and not room.mist_field.hunting, "Final cleanup leaves no attacking vines, root terrain or hunt")
	check(save.get_stele_state(&"vine_puzzle_high_swing") == 0 and save.get_stele_state(&"vine_combat_branch_arena") == 0 \
		and not save.has_completed(SaveProgressService.STORY_C1_XIAOSUI_MET) and save.get_inventory_items() == inventory, "Direct boss route grants only the relic without residents or steles")
	await stand(boss.position + Vector2(-70, 0))
	key()
	await process_frame
	check(story.dialogue != null and story.dialogue._label.text == "……这回，听得清林子里的声音了。" and paused, "First resident conversation is voluntary and pauses the world")
	await capture("deer_npc_dialogue_right")
	story.dialogue.advance()
	await capture("deer_npc_dialogue_left")
	key(KEY_ESCAPE)
	await process_frame
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_BODY_INSPECTED) and not paused, "Cancelled M11 retains victory but leaves inspection undone")
	clear_scene()
	await enter(fixture_intro())
	check(story.comic == null and boss.phase == 4 and boss.state == DeerBoss.State.COMPLETE and not boss.visible and story.resident != null, "Victory reload restores resident without battle or late intro")
	await capture("deer_victory_reentry")
	await stand(story.trace.position + Vector2(-45, 0))
	key()
	await process_frame
	check(story.dialogue != null and story.dialogue._label.text == "从这里过去了？", "M12 optional trace works even without M07 or M11")
	await capture("deer_forecourt_trace")
	story.dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_FORECOURT_TRACE_SEEN) and not save.has_completed(SaveProgressService.STORY_C1_DEER_BODY_INSPECTED), "Forecourt and corpse inspections settle independently")
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_WIND_SIGHTING) == 0, "Victory and M12 never backfill missed Wind comic")
	await stand(boss.position + Vector2(-70, 0))
	key()
	await process_frame
	story.dialogue.advance()
	story.dialogue.advance()
	story.dialogue.advance()
	check(save.has_completed(SaveProgressService.STORY_C1_DEER_BODY_INSPECTED), "M11 may complete after M12")
	check(story.choices != null and story.choices.options == ["再战？", "离开"] and paused, "First resident dialogue ends with rematch choices")
	story.choices.choose(1)
	story._process(0)
	check(story.body_prompt.available, "Resident remains interactable after completed conversation")
	await process_frame
	key()
	await process_frame
	check(story.choices != null and paused, "Repeat interaction offers optional conversation topics")
	key(KEY_2)
	await process_frame
	check(story.dialogue != null and story.dialogue._label.text.contains("根还活着"), "Forest topic uses resident dialogue")
	story.dialogue.advance()
	check(story.choices != null and story.choices.options == ["再战？", "离开"], "Existing topic reply ends with rematch choices")
	story.choices.choose(1)
	await process_frame
	await process_frame
	key()
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(story.choices == null and not paused and not room.player.input_frozen, "Escape exits topic menu and restores control")
	check(room._return_prompt.available and not paused, "All investigations leave return passage available")
	story._talk_to_resident()
	story.choices.choose(0)
	story.dialogue.advance()
	story.choices.choose(0)
	await create_timer(3.0).timeout
	room = current_scene as Chapter1DeerBossRoom
	story = room.story
	boss = room.deer
	check(story.is_rematch and story.comic == null and boss.phase == 1 and boss.is_physics_processing(), "Resident rematch starts full fight without intro comic")
	check(story.resident == null and not story.chapter_gate.visible, "Rematch has no resident or chapter portal during live combat")
	check(not (root.get_node("SceneTransition") as SceneTransitionService).deer_rematch_requested, "Rematch entry request consumed once")
	room.player.combat_stats.apply_health_damage(room.player.combat_stats.max_health)
	await process_frame
	await process_frame
	check(boss.phase == 1 and room.player.combat_stats.health > 0 and story.is_rematch, "Rematch death resets first phase and revives player")
	await prepare_human()
	await kill_human()
	check(story._settled and story.resident != null and not boss.visible, "Rematch final defeat restores resident NPC")
	check(story.reward_reveal == null and save.get_item_count(ItemCatalog.DEER_RELIC) == 1, "Rematch does not replay or duplicate first-clear reward")
	story._talk_to_resident()
	story.choices.choose(1)
	story.dialogue.advance()
	check(story.choices != null and story.choices.options == ["再战？", "离开"], "Resident can offer another rematch after victory")
	story.choices.choose(1)
	clear_scene()

	# Failure: the finished fight remains safe and settlement is explicitly retryable.
	seed_progress()
	await enter(fixture_intro(true))
	await prepare_human()
	var failed := FailedSave.new()
	failed._loaded = true
	story.save = failed
	await kill_human()
	check(story.victory_pending and story.resident == null and boss.visible and not failed.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and boss.state == DeerBoss.State.COMPLETE, "Failed victory save keeps safe body for retry without spawning resident")
	check(not story.trace.visible and not story.trace_prompt.available and not paused, "Unsaved victory does not unlock investigations or freeze player")
	failed.failing = false
	await stand(boss.position + Vector2(-70, 0))
	key()
	await process_frame
	check(failed.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED) and story.reward_reveal != null, "Body E retries victory first, then presents its reward")
	await dismiss_reward()
	await process_frame
	await process_frame
	key()
	await process_frame
	failed.failing = true
	story.dialogue.advance()
	story.dialogue.advance()
	story.dialogue.advance()
	check(story.choices != null and not failed.has_completed(SaveProgressService.STORY_C1_DEER_BODY_INSPECTED), "Failed M11 save never rolls back battle victory")
	key(KEY_2)
	await process_frame
	check(not paused and not room.player.input_frozen, "Can leave failed inspection safely")
	story.save = save
	failed.free()
	clear_scene()

	seed_progress()
	await enter(fixture_intro())
	check(paused and story.comic != null and not boss.is_physics_processing() and not save.has_completed(SaveProgressService.STORY_C1_DEER_ENCOUNTERED), "Ready M09 art reads before first actual attempt")
	clear_scene()
	await process_frame
	check(not paused and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == 0, "Interrupted intro leaves outcome unhandled and restores pause")
	await enter(fixture_intro())
	key(KEY_ESCAPE)
	await process_frame
	check(not paused and boss.is_physics_processing() and save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.SKIPPED, "M09 skip settles separately then starts real battle")
	clear_scene()
	await enter(fixture_intro())
	check(story.comic != null and story.comic.panel_index == 0 and boss.phase == 1, "Map re-entry after a skip offers full intro until watched")
	clear_scene()
	seed_progress()
	await enter(fixture_intro())
	key()
	await process_frame
	check(save.get_cinematic_status(SaveProgressService.CINEMATIC_C1_DEER_INTRO) == SaveProgressService.CinematicStatus.WATCHED and boss.is_physics_processing(), "Natural M09 ending records watched and starts battle")
	check(not save.has_completed(SaveProgressService.STORY_C1_DEER_DEFEATED), "Watching intro never awards victory")
	clear_scene()
	print("DEER STORY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
