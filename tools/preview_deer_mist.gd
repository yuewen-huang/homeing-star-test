extends SceneTree

class PreviewProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true
	func get_item_count(item_id: StringName) -> int:
		return 1 if item_id == ItemCatalog.VINE_SNARE else 0

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var player: LanPlayer
var output := "C:/Users/P6063166/.codex/visualizations/2026/10/10/01a123df-d0fc-7331-96ec-48167310c626/mist_redo"

func _initialize() -> void:
	call_deferred("run")

func advance(seconds: float) -> void:
	for i in ceili(seconds * 60):
		boss._physics_process(1.0 / 60)
		boss.vfx._process(1.0 / 60)
		room.mist_field._process(1.0 / 60)

func capture(name: String) -> void:
	boss._update_cloak()
	boss.vfx.queue_redraw()
	room.mist_field.update_material()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if OS.get_cmdline_user_args().has("--still") and name.get_slice("_", 1).is_valid_int():
		return
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func reset() -> void:
	Engine.time_scale = 1
	player.reset_after_map_fall(Vector2(1250, 555))
	player.combat_stats.restore_health()
	player.combat_stats.restore_poise()
	player.defense_state = LanPlayer.DefenseState.NONE
	player.input_frozen = false
	player.boss_controlled = false
	player.dodge_bullet_time_remaining = 0
	boss.reset_phase()
	boss.position = Vector2(1000, 555)
	boss.set_physics_process(false)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var progress := PreviewProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	boss = room.deer
	player = room.player
	boss.set_physics_process(false)
	player.set_physics_process(false)
	room.mist_field.set_process(false)
	await process_frame
	boss.vfx.set_process(false)
	reset()
	boss.start_attack(DeerBoss.State.HEAVY)
	for frame in 66:
		advance(1.0 / 20)
		await capture("wave_%03d" % frame)
		if frame == 20: await capture("warning")
		if frame == 38: await capture("wave_active")
	reset()
	boss.start_mist_hunt()
	boss._start_hunt_round()
	boss.use_vine_snare()
	for frame in 100:
		advance(1.0 / 20)
		await capture("snare_%03d" % frame)
		if frame == 15: await capture("snare_bound")
	room.queue_free()
	await process_frame
	(root.get_node("CombatFeedback") as CombatFeedbackService).impact_player.stop()
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_player.stop()
	(root.get_node("SceneTransition") as SceneTransitionService).music_player.stop()
	print("PREVIEW COMPLETE")
	OS.delay_msec(100)
	quit()
