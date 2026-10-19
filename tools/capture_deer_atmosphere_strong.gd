extends SceneTree
## Actual forest room, real deer actions, memory-only progress. args: directory [frames].
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var room: Chapter1DeerBossRoom
var deer: DeerBoss
var output := ""
var frames := false
var capture_actions := false
func _initialize() -> void: call_deferred("run")
func tick() -> void:
	deer._physics_process(1.0 / 60.0)
	deer.vfx._process(1.0 / 60.0)
func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	frames = args.size() > 1 and args[1] == "frames"
	capture_actions = args.size() > 1
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	original.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	for node in room.find_children("*", "WindSightingComic", true, false): node.abandoned.emit()
	await process_frame
	await process_frame
	deer = room.deer
	room.player.set_input_frozen(false)
	room.player.set_physics_process(false)
	room.player.reset_after_map_fall(Vector2(500, 555))
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	deer.manual_control = true
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	for phase in [1, 2, 3]:
		deer.phase = phase
		deer._recover(10.0)
		deer.position = Vector2(820, 555)
		deer.direction = -1
		deer._show_clip(&"idle_ING", 0)
		deer.vfx.reset_effects()
		deer.vfx.phase_atmosphere_enabled = true
		for i in 180: deer.vfx._process(1.0 / 60.0)
		await shot("phase%d_idle" % phase)
		if not capture_actions: continue
		var folder := output.path_join("phase%d" % phase)
		DirAccess.make_dir_recursive_absolute(folder)
		for i in (60 if frames else 0):
			deer.vfx._process(1.0 / 60.0)
			if i % 3 == 0: await shot("phase%d/frame_%04d" % [phase, i / 3])
		if phase == 3: deer.start_clash(&"red_finale", room.player.position.x)
		else: deer.start_attack(DeerBoss.State.HEAVY)
		var warning_captured := false
		var active_captured := false
		for i in 210:
			tick()
			if deer.vfx.red_warning.visible and deer.vfx.red_warning.frame == 1 and not warning_captured:
				warning_captured = true
				await shot("phase%d_warning" % phase)
			if deer.attack_hitbox.attack != null and not active_captured:
				active_captured = true
				await shot("phase%d_active" % phase)
			if frames and i % 6 == 0:
				await shot("phase%d/frame_%04d" % [phase, 20 + i / 6])
		await shot("phase%d_recovery" % phase)
		assert(warning_captured and active_captured, "Need real warning and active samples")
		print("CAPTURED PHASE ", phase)
	# Check the original gold charge cue against the stronger body atmosphere too.
	deer.phase = 1
	deer._recover(0.0)
	deer.position = Vector2(820, 555)
	deer.vfx.reset_effects()
	for i in 120: deer.vfx._process(1.0 / 60.0)
	deer.start_charge_at(room.player.position.x)
	var gold_captured := false
	for i in 120:
		tick()
		if deer.vfx.gold_warning.visible and deer.vfx.gold_warning.frame == 1:
			await shot("gold_warning")
			gold_captured = true
			break
	assert(gold_captured, "Need the actual gold warning peak")
	room.free()
	quit()
