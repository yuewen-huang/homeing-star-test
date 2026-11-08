extends SceneTree

class MemorySave extends SaveProgressService:
	var fail := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail

var checks := 0
var failures := 0
var field: Chapter2SaltField
var npc
var save: MemorySave
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code; e.keycode = code; e.pressed = true
	root.push_input(e)
	e = e.duplicate(); e.pressed = false; root.push_input(e)
	await process_frame
	await process_frame
func choose(index: int) -> void:
	npc.choices.choose(index)
	await process_frame
	await process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))
func enter() -> void:
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate()
	root.add_child(field); current_scene = field
	field.set_physics_process(false)
	npc = field.shibo
	await process_frame
	field.feet = npc.POINT + Vector2(-55, 0)
	field._sync_view(0)
	field.camera.position = field.pawn.position - Vector2(0, 75)
	field.camera.reset_smoothing()
	await process_frame
func run() -> void:
	print("Shibo test starting")
	var old := root.get_node("SaveProgress")
	root.remove_child(old); old.free()
	save = MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	print("Loading salt scene")
	await enter()
	var original_boss: int = field.state.boss_pile
	check(npc.can_interact(), "Optional NPC reachable beside loading point")
	var idle := npc.get_node("Idle") as AnimatedSprite2D
	check(idle.is_playing() and idle.sprite_frames.get_frame_count(&"idle") == 4, "Semi-chibi has four authored idle frames")
	var feet_before: Vector2 = npc.global_position
	idle.set_frame_and_progress(0, 0)
	for i in 108: await process_frame
	check(idle.frame != 0, "Idle advances naturally over time")
	check(npc.global_position == feet_before and idle.scale == Vector2.ONE, "Animation never bobs root or scales body")
	for i in 4:
		idle.pause()
		idle.set_frame_and_progress(i, 0)
		await capture("shibo_idle_%d" % i)
	idle.play(&"idle")
	await capture("shibo_world")
	await key(KEY_E)
	check(paused and field.pawn.player.input_frozen and npc.dialogue != null, "Real E opens intro and safely pauses hazards")
	await capture("lan_left")
	await key(KEY_E)
	await capture("shibo_right")
	await key(KEY_ESCAPE)
	check(not paused and not field.pawn.player.input_frozen, "Esc restores exploration")
	check(not save.has_completed(npc.INTRO), "Skipped intro never counted as read")
	await key(KEY_E)
	check(npc.choices != null, "Skipped intro allows topics immediately")
	await choose(0)
	check(npc.dialogue != null, "Tool topic accessible without intro prerequisite")
	await key(KEY_ESCAPE)
	check(not save.has_completed(npc.INTRO), "Skipped tool topic does not grant knowledge")
	await key(KEY_E); await choose(0)
	for i in 4: await key(KEY_E)
	check(save.has_completed(npc.INTRO) and not paused, "Reading all tool lines persists independent fact")
	await key(KEY_E); await key(KEY_ESCAPE)
	check(not paused and npc.choices == null, "Esc dismisses topic menu")
	save.fail = true
	await key(KEY_E); await choose(1)
	for i in 2: await key(KEY_E)
	check(not paused and not save.has_completed(npc.WIND), "Save failure closes conversation without false fact")
	save.fail = false
	check(field.state.boss_pile == original_boss and not field.boss_found, "Dialogue leaves boss discovery untouched")
	field.feet = field.RETURN_POINT; field._sync_view(0)
	check(field.can_return(), "Return gate unaffected")
	field.feet = npc.POINT + Vector2(-55, 0); field._sync_view(0)
	field.crab_encounter.active = true
	check(not npc.can_interact(), "Combat suppresses optional interaction")
	field.crab_encounter.active = false
	await key(KEY_E)
	field.free(); current_scene = null
	check(not paused, "Scene teardown restores pause even from topics")
	await enter()
	await key(KEY_E)
	check(npc.choices != null and save.has_completed(npc.INTRO), "Reentry preserves topics and knowledge")
	await key(KEY_ESCAPE)
	# Also verify the actual untouched dig entry without any NPC requirement.
	field.feet = field.piles[original_boss].ground_position
	field._sync_view(0)
	for i in 80: field.step_exploration(1.0 / 60.0, Vector2.ZERO, true, false)
	check(field.boss_found, "Normal boss excavation remains available")
	field.free(); current_scene = null
	print("Shibo: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
